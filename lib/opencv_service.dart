import 'dart:math' as math;
import 'dart:typed_data';

import 'package:opencv_dart/opencv_dart.dart';

/// A green object found in an image, together with everything the matcher needs.
///
/// The bounding box is kept as plain ints instead of an OpenCV `Rect` so a
/// `DetectedObject` can safely outlive the `Mat` it was produced from; the
/// native rect is rebuilt on demand via [buildRect] and disposed immediately.
class DetectedObject {
  final int rectX;
  final int rectY;
  final int rectWidth;
  final int rectHeight;

  String? label;
  double? matchDistance;

  /// 64x64 normalized binary matrix (1 = inside object, 0 = outside/hole).
  /// Row-major, length = matrixSize*matrixSize.
  List<int>? matrix;

  /// ORB/BRIEF descriptors for this object's ROI, flattened row-major into
  /// [orbDescriptorCount] x orbDescriptorBytes. Held as Dart bytes rather than
  /// a `Mat` so no native memory outlives the detection call.
  Uint8List? orbDescriptors;

  DetectedObject(this.rectX, this.rectY, this.rectWidth, this.rectHeight);

  int get width => rectWidth;
  int get height => rectHeight;
  int get area => rectWidth * rectHeight;

  int get orbDescriptorCount => orbDescriptors == null
      ? 0
      : orbDescriptors!.length ~/ OpenCVService.orbDescriptorBytes;

  bool get hasOrbDescriptors => orbDescriptorCount > 0;

  /// Builds a fresh native rect for this box. The caller owns the result and
  /// must dispose it.
  Rect buildRect() => Rect(rectX, rectY, rectWidth, rectHeight);

  /// This box clamped to a maxWidth x maxHeight image, as plain ints.
  ({int x, int y, int width, int height}) clampTo(int maxWidth, int maxHeight) {
    final x0 = rectX.clamp(0, maxWidth);
    final y0 = rectY.clamp(0, maxHeight);
    return (
      x: x0,
      y: y0,
      width: (rectX + rectWidth).clamp(0, maxWidth) - x0,
      height: (rectY + rectHeight).clamp(0, maxHeight) - y0,
    );
  }
}

/// Result of matching a detected object against a trained product.
class FeatureMatch {
  final String name;

  /// % difference between detected and reference dimensions (0 = identical).
  final double dimensionScore;

  /// Feature similarity in 0..1 (higher = better). This is the ORB
  /// ratio-test score when both sides carry descriptors, otherwise the 64x64
  /// matrix similarity for products trained before ORB existed.
  final double featureScore;

  /// Weighted blend of dimension similarity and [featureScore], 0..1.
  final double combinedScore;

  FeatureMatch({
    required this.name,
    required this.dimensionScore,
    required this.featureScore,
    required this.combinedScore,
  });
}

/// Core OpenCV green-object detection + ORB feature pipeline.
///
/// Detection steps: BGR -> HSV -> inRange (green mask) -> morphology close/open
/// -> dilate/erode -> findContours -> merge nearby -> filter by area. The mask
/// is built once and shared by the matrix extraction, and the bounding boxes are
/// reused for annotation, so a single detection pass serves the whole screen.
class OpenCVService {
  // Combined range to cover old light green (H 25-45) + new saturated green (H 68-98)
  static const _lowerGreen = (25.0, 12.0, 35.0);
  static const _upperGreen = (98.0, 170.0, 185.0);

  static const _minArea = 500;
  static const _mergeDistance = 80;

  /// Matrix grid resolution. Configuration chosen: 64x64.
  static const matrixSize = 64;

  /// Maximum ORB keypoints extracted per object ROI.
  static const orbFeatures = 500;

  /// ORB/BRIEF descriptor is 256 bits = 32 bytes.
  static const orbDescriptorBytes = 32;

  /// Lowe's ratio test: a descriptor matches only when its best neighbour is
  /// closer than this fraction of its second best.
  static const loweRatio = 0.75;

  /// Absolute Hamming ceiling (out of 256 bits) a descriptor pair may differ by
  /// and still be considered a correspondence.
  static const orbMaxHamming = 32;

  /// ORB needs a patch of 31x31 px around each keypoint, so ROIs smaller than
  /// this cannot produce usable descriptors.
  static const orbMinSide = 32;

  /// Detects all green objects in [bytes], returning their rects, 64x64
  /// matrices and (unless [extractOrb] is false) ORB descriptors.
  static List<DetectedObject> detectGreenObjectsBytes(Uint8List bytes, {bool extractOrb = true}) {
    final img = imdecode(bytes, IMREAD_COLOR);
    if (img.isEmpty) {
      img.dispose();
      return const [];
    }
    try {
      return _findGreenObjects(img, extractOrb: extractOrb);
    } finally {
      img.dispose();
    }
  }

  /// Same as [detectGreenObjectsBytes] for an already decoded [Mat].
  static List<DetectedObject> detectGreenObjects(Mat img, {bool extractOrb = true}) =>
      _findGreenObjects(img, extractOrb: extractOrb);

  /// Draws boxes and labels on objects that were already produced by
  /// [detectGreenObjectsBytes].
  ///
  /// This deliberately does **not** re-run detection: the boxes come from the
  /// very same pass that produced the match results, so drawn labels can never
  /// drift out of alignment with the scores shown next to them.
  static Uint8List? annotateObjects(Uint8List source, List<DetectedObject> objects, {bool showGrid = false}) {
    if (objects.isEmpty) return null;
    final img = imdecode(source, IMREAD_COLOR);
    if (img.isEmpty) {
      img.dispose();
      return null;
    }
    try {
      for (final obj in objects) {
        _drawBox(img, obj, obj.label);
        if (showGrid) _drawGrid(img, obj);
      }
      final (ok, bytes) = imencode('.jpg', img);
      return ok ? bytes : null;
    } finally {
      img.dispose();
    }
  }

  /// Convenience wrapper that re-detects before annotating. Prefer
  /// [annotateObjects] when the objects are already at hand.
  static Uint8List? drawAnnotatedBytes(Uint8List source, List<String?> labels, {bool showGrid = false}) {
    final objects = detectGreenObjectsBytes(source, extractOrb: false);
    if (objects.isEmpty) return null;
    for (var i = 0; i < objects.length; i++) {
      objects[i].label = i < labels.length ? labels[i] : null;
    }
    return annotateObjects(source, objects, showGrid: showGrid);
  }

  /// Renders a single matrix (64x64) as a zoomed grid image (white=1, black=0)
  /// with grid lines. [cellSize] controls zoom (e.g. 4 => 256x256 image).
  static Uint8List matrixToGridImage(List<int> matrix, {int cellSize = 4, String? label}) {
    final size = matrixSize * cellSize;
    final extra = label != null ? 28 : 0;
    final img = Mat.zeros(size + extra, size, MatType.CV_8UC3);
    try {
      // fill cells
      for (var r = 0; r < matrixSize; r++) {
        for (var c = 0; c < matrixSize; c++) {
          final v = matrix[r * matrixSize + c];
          final color = v == 1 ? Scalar(255, 255, 255) : Scalar(0, 0, 0);
          final x = c * cellSize, y = r * cellSize;
          rectangle(img, Rect(x, y, cellSize, cellSize), color, thickness: -1);
        }
      }
      // grid lines (thin grey)
      final gridColor = Scalar(80, 80, 80);
      for (var i = 0; i <= matrixSize; i++) {
        final p = i * cellSize;
        line(img, Point(p, 0), Point(p, size), gridColor, thickness: 1);
        line(img, Point(0, p), Point(size, p), gridColor, thickness: 1);
      }
      // outer border green
      rectangle(img, Rect(0, 0, size, size), Scalar(0, 255, 0), thickness: 2);
      if (label != null) {
        putText(img, label, Point(6, size + 20), FONT_HERSHEY_SIMPLEX, 0.6, Scalar(0, 255, 0), thickness: 2);
      }
      final (ok, bytes) = imencode('.jpg', img);
      return ok ? bytes : Uint8List(0);
    } finally {
      img.dispose();
    }
  }

  /// Extracts ORB (Oriented FAST + rotated BRIEF) descriptors from [roi].
  ///
  /// Returns the descriptors flattened row-major into n x orbDescriptorBytes,
  /// or null when the ROI is too small or yields no keypoints. Every native
  /// object created here is released before returning.
  static Uint8List? extractOrbFeatures(Mat roi) {
    if (roi.isEmpty || roi.rows < orbMinSide || roi.cols < orbMinSide) return null;

    final noMask = Mat.empty();
    Mat? gray;
    ORB? orb;
    VecKeyPoint? keypoints;
    Mat? descriptors;
    try {
      gray = switch (roi.channels) {
        1 => roi.clone(),
        4 => cvtColor(roi, COLOR_BGRA2GRAY),
        _ => cvtColor(roi, COLOR_BGR2GRAY),
      };
      orb = ORB.create(nFeatures: orbFeatures);
      final result = orb.detectAndCompute(gray, noMask);
      keypoints = result.$1;
      descriptors = result.$2;
      if (descriptors.isEmpty || descriptors.cols != orbDescriptorBytes) return null;
      // `data` is a *view* onto native memory, so copy it before disposal.
      return Uint8List.fromList(descriptors.data);
    } catch (_) {
      // ORB throws on ROIs smaller than its patch; treat that as "no features".
      return null;
    } finally {
      _guard(noMask.dispose);
      _guard(() => keypoints?.dispose());
      _guard(() => descriptors?.dispose());
      _guard(() => gray?.dispose());
      _guard(() => orb?.dispose());
    }
  }

  /// ORB similarity ratio between two descriptor sets, in 0..1 (higher = better).
  ///
  /// Both sets are flat row-major orbDescriptorBytes-byte descriptors. This is
  /// the standard binary-descriptor pipeline: for every reference descriptor,
  /// find the 2 nearest test descriptors by Hamming distance and keep it only
  /// when `best < loweRatio * secondBest` (Lowe's ratio test). The score is
  /// `goodMatches / referenceCount`, so 0.0 means "no match ratio at all".
  ///
  /// The arithmetic is done in Dart on purpose instead of going through
  /// `BFMatcher.knnMatch`: in dartcv4 1.1.8 `VecDMatch.operator []` hands back
  /// a `DMatch` wrapper whose `calloc.nativeFree` finalizer is attached to a
  /// pointer still owned by the parent vector, so reading match distances
  /// through the binding risks a double free. This is the same computation
  /// (Hamming + k=2 + ratio test) and needs no native allocation at all.
  static double matchOrbDescriptors(List<int>? reference, List<int>? test) {
    if (reference == null || test == null) return 0.0;
    final refCount = reference.length ~/ orbDescriptorBytes;
    final testCount = test.length ~/ orbDescriptorBytes;
    if (refCount == 0 || testCount == 0) return 0.0;

    if (testCount < 2) {
      // Not enough candidates for a ratio test; fall back to an absolute
      // Hamming ceiling so a single unrelated descriptor cannot score 1.0.
      var near = 0;
      for (var q = 0; q < refCount; q++) {
        if (_nearestHamming(reference, q, test, testCount) <= orbMaxHamming) near++;
      }
      return (near / refCount).clamp(0.0, 1.0);
    }

    var good = 0;
    for (var q = 0; q < refCount; q++) {
      final qOff = q * orbDescriptorBytes;
      var best = 1 << 30;
      var second = 1 << 30;
      for (var t = 0; t < testCount; t++) {
        final d = _hamming(reference, qOff, test, t * orbDescriptorBytes);
        if (d < best) {
          second = best;
          best = d;
        } else if (d < second) {
          second = d;
        }
      }
      if (best <= orbMaxHamming && best < loweRatio * second) good++;
    }
    return (good / refCount).clamp(0.0, 1.0);
  }

  static int _nearestHamming(List<int> reference, int queryIndex, List<int> test, int testCount) {
    final qOff = queryIndex * orbDescriptorBytes;
    var best = 1 << 30;
    for (var t = 0; t < testCount; t++) {
      final d = _hamming(reference, qOff, test, t * orbDescriptorBytes);
      if (d < best) best = d;
    }
    return best;
  }

  static int _hamming(List<int> a, int aOffset, List<int> b, int bOffset) {
    var d = 0;
    for (var i = 0; i < orbDescriptorBytes; i++) {
      d += _popCount(a[aOffset + i] ^ b[bOffset + i]);
    }
    return d;
  }

  static int _popCount(int v) {
    var x = v - ((v >> 1) & 0x55);
    x = (x & 0x33) + ((x >> 2) & 0x33);
    x = (x + (x >> 4)) & 0x0f;
    return x;
  }

  /// Distance between two (w,h) pairs as a percent (0 = identical),
  /// considering both normal and rotated (swapped) orientation.
  ///
  /// Non-positive reference dimensions are treated as 1 so a malformed
  /// products.json can never produce Infinity/NaN scores.
  static double distance(int w1, int h1, int w2, int h2) {
    final rw = w2 <= 0 ? 1 : w2;
    final rh = h2 <= 0 ? 1 : h2;
    final dNormal = (math.max((w1 - rw).abs() / rw, (h1 - rh).abs() / rh)) * 100;
    final dRotated = (math.max((w1 - rh).abs() / rh, (h1 - rw).abs() / rw)) * 100;
    return math.min(dNormal, dRotated);
  }

  /// Normalized Cross-Correlation distance between two matrices.
  ///
  /// Returns a value in [0,1] where 0 = perfectly correlated (identical) and
  /// 1 = completely uncorrelated. Small shifts of a few cells are handled by
  /// trying offsets, making it robust to minor misalignment.
  static double nccDistance(List<int> a, List<int> b) {
    if (a.length != b.length || a.length != matrixSize * matrixSize) return 1.0;

    double best = -1.0;
    const maxShift = 3;
    for (var dy = -maxShift; dy <= maxShift; dy++) {
      for (var dx = -maxShift; dx <= maxShift; dx++) {
        final corr = _nccAtOffset(a, b, dx, dy);
        if (corr > best) best = corr;
      }
    }
    // Best possible correlation is 1.0 (identical). Convert to distance.
    return (1.0 - best).clamp(0.0, 1.0);
  }

  static double _nccAtOffset(List<int> a, List<int> b, int dx, int dy) {
    // Slide b over a by (dx, dy). Only overlap region is compared.
    var sumA = 0.0, sumB = 0.0;
    var n = 0;
    for (var r = 0; r < matrixSize; r++) {
      final br = r + dy;
      if (br < 0 || br >= matrixSize) continue;
      for (var c = 0; c < matrixSize; c++) {
        final bc = c + dx;
        if (bc < 0 || bc >= matrixSize) continue;
        sumA += a[r * matrixSize + c];
        sumB += b[br * matrixSize + bc];
        n++;
      }
    }
    if (n == 0) return -1.0;
    final meanA = sumA / n;
    final meanB = sumB / n;
    var num = 0.0, denA = 0.0, denB = 0.0;
    for (var r = 0; r < matrixSize; r++) {
      final br = r + dy;
      if (br < 0 || br >= matrixSize) continue;
      for (var c = 0; c < matrixSize; c++) {
        final bc = c + dx;
        if (bc < 0 || bc >= matrixSize) continue;
        final va = a[r * matrixSize + c] - meanA;
        final vb = b[br * matrixSize + bc] - meanB;
        num += va * vb;
        denA += va * va;
        denB += vb * vb;
      }
    }
    final denom = math.sqrt(denA * denB);
    if (denom == 0) return 0.0;
    return num / denom;
  }

  static void _drawGrid(Mat img, DetectedObject obj) {
    final stepX = obj.rectWidth / matrixSize;
    final stepY = obj.rectHeight / matrixSize;
    final color = Scalar(0, 255, 255); // yellow grid
    for (var i = 1; i < matrixSize; i++) {
      final x = (obj.rectX + i * stepX).round();
      line(img, Point(x, obj.rectY), Point(x, obj.rectY + obj.rectHeight), color, thickness: 1);
      final y = (obj.rectY + i * stepY).round();
      line(img, Point(obj.rectX, y), Point(obj.rectX + obj.rectWidth, y), color, thickness: 1);
    }
  }

  static void _drawBox(Mat img, DetectedObject obj, String? label) {
    final box = obj.buildRect();
    try {
      rectangle(img, box, Scalar(0, 255, 0), thickness: 4);
    } finally {
      box.dispose();
    }

    if (label == null || label.isEmpty) return;

    const fontSize = 1.0;
    const thickness = 3;
    final textHeight = 34 * fontSize;
    final textY =
        (obj.rectY - 10) >= textHeight.toInt() ? obj.rectY - 10 : obj.rectY + textHeight.toInt() + 4;
    final bgTop = textY - textHeight.toInt() - 8;
    final bgWidth = (label.length * 21 * fontSize).toInt() + 24;
    final bgHeight = textHeight.toInt() + 16;

    final bx = obj.rectX == 0 ? 0 : obj.rectX;
    final by = bgTop < 0 ? 0 : bgTop;
    final bg = Rect(bx, by, bgWidth, bgHeight);
    try {
      rectangle(img, bg, Scalar(0, 255, 0), thickness: -1);
      putText(
        img,
        label,
        Point(bx + 12, textY),
        FONT_HERSHEY_SIMPLEX,
        fontSize,
        Scalar(0, 0, 0),
        thickness: thickness,
      );
    } finally {
      bg.dispose();
    }
  }

  /// Builds the green mask once, then finds the merged object rects.
  static List<DetectedObject> _findGreenObjects(Mat img, {required bool extractOrb}) {
    final hsv = cvtColor(img, COLOR_BGR2HSV);
    final mask = inRangebyScalar(
      hsv,
      Scalar(_lowerGreen.$1, _lowerGreen.$2, _lowerGreen.$3),
      Scalar(_upperGreen.$1, _upperGreen.$2, _upperGreen.$3),
    );
    hsv.dispose();

    final kernel = getStructuringElement(MORPH_RECT, (10, 10));
    final closed = morphologyEx(mask, MORPH_CLOSE, kernel);
    final opened = morphologyEx(closed, MORPH_OPEN, kernel);
    final kernelLarge = getStructuringElement(MORPH_RECT, (20, 20));
    final dilated = dilate(opened, kernelLarge, iterations: 2);
    final eroded = erode(dilated, kernelLarge, iterations: 2);

    final baseRects = <({int x, int y, int w, int h})>[];
    final (contours, hierarchy) = findContours(eroded, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);
    for (final c in contours) {
      final rect = boundingRect(c);
      try {
        if (rect.width * rect.height > _minArea) {
          baseRects.add((x: rect.x, y: rect.y, w: rect.width, h: rect.height));
        }
      } finally {
        rect.dispose();
      }
    }

    _batchDispose([closed, opened, dilated, eroded, kernel, kernelLarge]);
    // `contours` owns every VecPoint handed out by the loop above, so only the
    // parent vectors are released here.
    _guard(contours.dispose);
    _guard(hierarchy.dispose);

    final mergedRects = _mergeNearbyRects(baseRects, distanceThreshold: _mergeDistance);

    // One detection pass: the mask feeds the matrix, the source image feeds ORB.
    final objects = <DetectedObject>[];
    for (final r in mergedRects) {
      final obj = DetectedObject(r.x, r.y, r.w, r.h);
      obj.matrix = _matrixFromMask(mask, obj);
      if (extractOrb) {
        final roi = _roiOf(img, obj);
        if (roi != null) {
          try {
            obj.orbDescriptors = extractOrbFeatures(roi);
          } finally {
            roi.dispose();
          }
        }
      }
      objects.add(obj);
    }

    mask.dispose();
    return objects;
  }

  /// Crops [obj] out of [img] as a new (owned) single-region Mat.
  static Mat? _roiOf(Mat img, DetectedObject obj) {
    final r = obj.clampTo(img.cols, img.rows);
    if (r.width <= 0 || r.height <= 0) return null;
    final roiRect = Rect(r.x, r.y, r.width, r.height);
    try {
      return Mat.fromMat(img, roi: roiRect);
    } finally {
      roiRect.dispose();
    }
  }

  /// Builds a normalized matrixSize x matrixSize binary matrix for the object
  /// inside the shared green [mask].
  ///
  /// Cells are 1 where the object body is present and 0 for background AND for
  /// internal holes (so holes distinguish products).
  static List<int> _matrixFromMask(Mat mask, DetectedObject obj) {
    final out = List<int>.filled(matrixSize * matrixSize, 0);
    final r = obj.clampTo(mask.cols, mask.rows);
    if (r.width <= 0 || r.height <= 0) return out;

    final roiRect = Rect(r.x, r.y, r.width, r.height);
    final roi = Mat.fromMat(mask, roi: roiRect);
    roiRect.dispose();

    // 1) Filled object body (outer contour filled to 255), closing holes.
    final filled = roi.clone();
    final (fc, hierarchy) = findContours(roi, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);
    for (final c in fc) {
      final wrapped = VecVecPoint.fromVecPoint(c);
      try {
        drawContours(filled, wrapped, -1, Scalar(255), thickness: -1);
      } finally {
        wrapped.dispose();
      }
    }
    _guard(fc.dispose);
    _guard(hierarchy.dispose);

    // 2) Holes = pixels inside the filled body that are NOT green.
    final notRoi = bitwiseNOT(roi);
    final holes = bitwiseAND(filled, notRoi);

    // 3) Final body-with-holes: start from filled, zero-out the holes.
    final body = filled.clone();
    body.setTo(Scalar(0), mask: holes);

    // 4) Resize to matrixSize x matrixSize (INTER_NEAREST keeps binary crisp).
    final resized = resize(body, (matrixSize, matrixSize), interpolation: INTER_NEAREST);

    // 5) Read row-major cell values -> 1 if >127 else 0.
    for (var row = 0; row < matrixSize; row++) {
      for (var col = 0; col < matrixSize; col++) {
        out[row * matrixSize + col] = resized.atNum(row, col) > 127 ? 1 : 0;
      }
    }

    _batchDispose([roi, filled, notRoi, holes, body, resized]);
    return out;
  }

  /// Merges rects whose centers are within [distanceThreshold] pixels into a
  /// single bounding rect (same algorithm as the Python `merge_nearby_contours`).
  static List<({int x, int y, int w, int h})> _mergeNearbyRects(
    List<({int x, int y, int w, int h})> rects, {
    required int distanceThreshold,
  }) {
    if (rects.isEmpty) return const [];
    final used = List<bool>.filled(rects.length, false);
    final merged = <({int x, int y, int w, int h})>[];

    for (var i = 0; i < rects.length; i++) {
      if (used[i]) continue;
      final group = <({int x, int y, int w, int h})>[rects[i]];
      used[i] = true;

      final cx1 = rects[i].x + rects[i].w ~/ 2;
      final cy1 = rects[i].y + rects[i].h ~/ 2;

      for (var j = i + 1; j < rects.length; j++) {
        if (used[j]) continue;
        final cx2 = rects[j].x + rects[j].w ~/ 2;
        final cy2 = rects[j].y + rects[j].h ~/ 2;
        final dx = cx1 - cx2;
        final dy = cy1 - cy2;
        if (math.sqrt(dx * dx + dy * dy) < distanceThreshold) {
          group.add(rects[j]);
          used[j] = true;
        }
      }

      var minX = group.first.x, minY = group.first.y;
      var maxX = group.first.x + group.first.w, maxY = group.first.y + group.first.h;
      for (final g in group) {
        minX = minX < g.x ? minX : g.x;
        minY = minY < g.y ? minY : g.y;
        maxX = maxX > g.x + g.w ? maxX : g.x + g.w;
        maxY = maxY > g.y + g.h ? maxY : g.y + g.h;
      }
      merged.add((x: minX, y: minY, w: maxX - minX, h: maxY - minY));
    }
    return merged;
  }

  static void _batchDispose(List<Mat> mats) {
    for (final m in mats) {
      _guard(m.dispose);
    }
  }

  /// Native handles are best-effort released: a throw here must never mask the
  /// result the caller is actually after.
  static void _guard(void Function() release) {
    try {
      release();
    } catch (_) {}
  }
}
