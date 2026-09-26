import 'dart:typed_data';
import 'dart:math' as math;

import 'package:opencv_dart/opencv_dart.dart';

class DetectedObject {
  final Rect rect;
  final int width;
  final int height;
  String? label;
  double? matchDistance;

  /// 64x64 normalized binary matrix (1 = inside object, 0 = outside/hole).
  /// Row-major, length = matrixSize*matrixSize.
  List<int>? matrix;

  DetectedObject(this.rect)
      : width = rect.width,
        height = rect.height;

  int get area => rect.width * rect.height;
}

/// Result of matching a single detected object (dimensions + matrix).
class MatrixMatch {
  final String name;
  final double dimensionScore;
  final double matrixScore;
  final double combinedScore;

  MatrixMatch({
    required this.name,
    required this.dimensionScore,
    required this.matrixScore,
    required this.combinedScore,
  });
}

/// Core OpenCV green-object detection pipeline, ported from the Python script.
///
/// Steps: BGR -> HSV -> inRange (green mask) -> morphology close/open
/// -> dilate/erode -> findContours -> merge nearby -> filter by area.
class OpenCVService {
  // Combined range to cover old light green (H 25-45) + new saturated green (H 68-98)
  static const _lowerGreen = (25.0, 12.0, 35.0);
  static const _upperGreen = (98.0, 170.0, 185.0);

  static const _minArea = 500;
  static const _mergeDistance = 80;

  /// Matrix grid resolution (65 * 65 cells). Configuration chosen: 64x64.
  static const matrixSize = 64;

  /// Detects ALL green objects in the image bytes, returning their
  /// dimensions. Empty list if none found.
  static List<DetectedObject> detectGreenObjectsBytes(Uint8List bytes) {
    final img = imdecode(bytes, IMREAD_COLOR);
    if (img.isEmpty) return const [];
    try {
      return _findGreenObjects(img);
    } finally {
      img.dispose();
    }
  }

  /// Public: expose the rects + matrices for a decoded [Mat].
  static List<DetectedObject> detectGreenObjects(Mat img) => _findGreenObjects(img);

  /// Draws a bounding box + optional label on EVERY detected green object and
  /// returns the annotated JPEG bytes. [labels] provides the name to draw for
  /// each object (index-aligned with detection order). Returns null if none.
  /// When [showGrid] is true, draws the 64×64 grid lines inside each box.
  static Uint8List? drawAnnotatedBytes(Uint8List source, List<String?> labels, {bool showGrid = false}) {
    final img = imdecode(source, IMREAD_COLOR);
    if (img.isEmpty) return null;
    try {
      final objects = _findGreenObjects(img);
      if (objects.isEmpty) return null;

      for (var i = 0; i < objects.length; i++) {
        final label = i < labels.length ? labels[i] : null;
        _drawBox(img, objects[i].rect, label);
        if (showGrid) _drawGrid(img, objects[i].rect);
      }

      final (ok, bytes) = imencode('.jpg', img);
      return ok ? bytes : null;
    } finally {
      img.dispose();
    }
  }

  /// Renders a single matrix (64×64) as a zoomed grid image (white=1, black=0)
  /// with grid lines. [cellSize] controls zoom (e.g. 4 => 256×256 image).
  static Uint8List matrixToGridImage(List<int> matrix, {int cellSize = 4, String? label}) {
    final size = matrixSize * cellSize;
    final extra = label != null ? 28 : 0;
    final img = Mat.zeros(size + extra, size, MatType.CV_8UC3);
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
    img.dispose();
    return ok ? bytes : Uint8List(0);
  }

  static void _drawGrid(Mat img, Rect rect) {
    final stepX = rect.width / matrixSize;
    final stepY = rect.height / matrixSize;
    final color = Scalar(0, 255, 255); // yellow grid
    for (var i = 1; i < matrixSize; i++) {
      final x = (rect.x + i * stepX).round();
      line(img, Point(x, rect.y), Point(x, rect.y + rect.height), color, thickness: 1);
      final y = (rect.y + i * stepY).round();
      line(img, Point(rect.x, y), Point(rect.x + rect.width, y), color, thickness: 1);
    }
  }

  static void _drawBox(Mat img, Rect rect, String? label) {
    rectangle(img, rect, Scalar(0, 255, 0), thickness: 4);

    if (label == null || label.isEmpty) return;

    const fontSize = 1.0;
    const thickness = 3;
    final textHeight = 34 * fontSize;
    final textY = (rect.y - 10) >= textHeight.toInt() ? rect.y - 10 : rect.y + textHeight.toInt() + 4;
    final bgTop = textY - textHeight.toInt() - 8;
    final bgWidth = (label.length * 21 * fontSize).toInt() + 24;
    final bgHeight = textHeight.toInt() + 16;

    final bx = rect.x == 0 ? 0 : rect.x;
    final by = bgTop < 0 ? 0 : bgTop;
    rectangle(img, Rect(bx, by, bgWidth, bgHeight), Scalar(0, 255, 0), thickness: -1);
    putText(
      img,
      label,
      Point(bx + 12, textY),
      FONT_HERSHEY_SIMPLEX,
      fontSize,
      Scalar(0, 0, 0),
      thickness: thickness,
    );
  }

  /// Finds all green objects (rects) and computes each one's 64x64 matrix.
  static List<DetectedObject> _findGreenObjects(Mat img) {
    final hsv = cvtColor(img, COLOR_BGR2HSV);
    final mask = inRangebyScalar(
      hsv,
      Scalar(_lowerGreen.$1, _lowerGreen.$2, _lowerGreen.$3),
      Scalar(_upperGreen.$1, _upperGreen.$2, _upperGreen.$3),
    );

    final kernel = getStructuringElement(MORPH_RECT, (10, 10));
    final closed = morphologyEx(mask, MORPH_CLOSE, kernel);
    final opened = morphologyEx(closed, MORPH_OPEN, kernel);
    final kernelLarge = getStructuringElement(MORPH_RECT, (20, 20));
    final dilated = dilate(opened, kernelLarge, iterations: 2);
    final eroded = erode(dilated, kernelLarge, iterations: 2);

    final (contours, _) = findContours(eroded, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);

    // Base rects from contours
    final baseRects = <Rect>[];
    for (final c in contours) {
      final rect = boundingRect(c);
      if (rect.width * rect.height > _minArea) {
        baseRects.add(rect);
      }
    }

    _batchDispose([hsv, mask, closed, opened, dilated, eroded, kernel, kernelLarge]);

    final mergedRects = _mergeNearbyRects(baseRects, distanceThreshold: _mergeDistance);

    // Compute matrix per merged rect using the raw binary mask
    final objects = <DetectedObject>[];
    for (final rect in mergedRects) {
      final obj = DetectedObject(rect);
      obj.matrix = _extractMatrix(img, rect);
      objects.add(obj);
    }
    return objects;
  }

  /// Builds a normalized matrixSize x matrixSize binary matrix for the object
  /// inside [rect]. Cells are 1 where the object body is present and 0 for
  /// background AND for internal holes (so holes distinguish products).
  static List<int> _extractMatrix(Mat img, Rect rect) {
    // Clamp rect into image bounds
    final rx = rect.x.clamp(0, img.cols);
    final ry = rect.y.clamp(0, img.rows);
    final rw = (rect.x + rect.width).clamp(0, img.cols) - rx;
    final rh = (rect.y + rect.height).clamp(0, img.rows) - ry;
    final roiRect = Rect(rx, ry, rw, rh);

    final hsv = cvtColor(img, COLOR_BGR2HSV);
    final mask = inRangebyScalar(
      hsv,
      Scalar(_lowerGreen.$1, _lowerGreen.$2, _lowerGreen.$3),
      Scalar(_upperGreen.$1, _upperGreen.$2, _upperGreen.$3),
    );
    final roi = Mat.fromMat(mask, roi: roiRect);
    // mask is a single-channel binary Mat (0/255). Work with it directly.

    // 1) Filled object body (outer contour filled to 255), closing holes.
    final filled = roi.clone();
    final (fc, _) = findContours(roi, RETR_EXTERNAL, CHAIN_APPROX_SIMPLE);
    for (final c in fc) {
      drawContours(filled, VecVecPoint.fromVecPoint(c), -1, Scalar(255), thickness: -1);
    }

    // 2) Holes = pixels inside the filled body that are NOT green (inverted roi).
    //    holes = filled AND (NOT roi)
    final notRoi = bitwiseNOT(roi);
    final holes = bitwiseAND(filled, notRoi);

    // 3) Final body-with-holes: start from filled, zero-out the holes.
    final body = filled.clone();
    body.setTo(Scalar(0), mask: holes);

    // 4) Resize to matrixSize x matrixSize (INTER_NEAREST keeps binary crisp).
    final resized = resize(body, (matrixSize, matrixSize), interpolation: INTER_NEAREST);

    // 5) Read row-major cell values -> 1 if >127 else 0.
    final out = List<int>.filled(matrixSize * matrixSize, 0);
    for (var r = 0; r < matrixSize; r++) {
      for (var c = 0; c < matrixSize; c++) {
        final v = resized.atNum(r, c);
        out[r * matrixSize + c] = v > 127 ? 1 : 0;
      }
    }

    _batchDispose([
      hsv, mask, roi, filled, notRoi, holes, body, resized,
    ]);
    return out;
  }

  /// Merges rects whose centers are within [distanceThreshold] pixels into a
  /// single bounding rect (same algorithm as the Python `merge_nearby_contours`).
  static List<Rect> _mergeNearbyRects(List<Rect> rects, {required int distanceThreshold}) {
    if (rects.isEmpty) return const [];
    final used = List<bool>.filled(rects.length, false);
    final merged = <Rect>[];

    for (var i = 0; i < rects.length; i++) {
      if (used[i]) continue;
      final group = <Rect>[rects[i]];
      used[i] = true;

      final x1 = rects[i].x, y1 = rects[i].y;
      final w1 = rects[i].width, h1 = rects[i].height;
      final cx1 = x1 + w1 ~/ 2, cy1 = y1 + h1 ~/ 2;

      for (var j = i + 1; j < rects.length; j++) {
        if (used[j]) continue;
        final rx = rects[j].x, ry = rects[j].y;
        final rw = rects[j].width, rh = rects[j].height;
        final cx2 = rx + rw ~/ 2, cy2 = ry + rh ~/ 2;
        final dist = math.sqrt(math.pow(cx1 - cx2, 2) + math.pow(cy1 - cy2, 2));
        if (dist < distanceThreshold) {
          group.add(rects[j]);
          used[j] = true;
        }
      }

      int minX = group.first.x, minY = group.first.y;
      int maxX = group.first.x + group.first.width, maxY = group.first.y + group.first.height;
      for (final g in group) {
        minX = minX < g.x ? minX : g.x;
        minY = minY < g.y ? minY : g.y;
        maxX = maxX > g.x + g.width ? maxX : g.x + g.width;
        maxY = maxY > g.y + g.height ? maxY : g.y + g.height;
      }
      merged.add(Rect(minX, minY, maxX - minX, maxY - minY));
    }
    return merged;
  }

  static void _batchDispose(List<Mat> mats) {
    for (final m in mats) {
      try {
        m.dispose();
      } catch (_) {}
    }
  }

  /// Distance between two (w,h) pairs as a percent (0 = identical),
  /// considering both normal and rotated (swapped) orientation.
  static double distance(int w1, int h1, int w2, int h2) {
    final dNormal = (math.max((w1 - w2).abs() / w2, (h1 - h2).abs() / h2)) * 100;
    final dRotated = (math.max((w1 - h2).abs() / h2, (h1 - w2).abs() / w2)) * 100;
    return math.min(dNormal, dRotated);
  }

  /// Normalized Cross-Correlation distance between two matrices.
  ///
  /// Returns a value in [0,1] where 0 = perfectly correlated (identical) and
  /// 1 = completely uncorrelated. Small shifts/shifts of a few cells are
  /// handled by trying offsets, making it robust to minor misalignment.
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
    var d = (1.0 - best).clamp(0.0, 1.0);
    return d;
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
        final va = a[r * matrixSize + c];
        final vb = b[br * matrixSize + bc];
        sumA += va;
        sumB += vb;
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
}
