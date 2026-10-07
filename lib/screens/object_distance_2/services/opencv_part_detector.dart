import 'dart:typed_data';

import 'package:opencv_dart/opencv.dart' as cv;

class DetectedPartDimensions {
  final double lengthPx;
  final double widthPx;

  const DetectedPartDimensions({
    required this.lengthPx,
    required this.widthPx,
  });
}

class OpenCvPartDetector {

  static Future<DetectedPartDimensions?> detect(
      Uint8List imageBytes,
      ) async {

    final image = cv.imdecode(
      imageBytes,
      cv.IMREAD_COLOR,
    );

    if (image.rows <= 0 ||
        image.cols <= 0) {
      return null;
    }

    /*
     * Convert to grayscale.
     */
    final gray = cv.cvtColor(
      image,
      cv.COLOR_BGR2GRAY,
    );

    /*
     * Binary threshold.
     *
     * This is intentionally simple for the
     * first real distance test.
     */
    final result = cv.threshold(
      gray,
      100,
      255,
      cv.THRESH_BINARY_INV,
    );

    final binary = result.$2;

    /*
     * Find external contours.
     */
    final contoursResult = cv.findContours(
      binary,
      cv.RETR_EXTERNAL,
      cv.CHAIN_APPROX_SIMPLE,
    );

    final contours = contoursResult.$1;

    if (contours.isEmpty) {
      return null;
    }

    double largestArea = 0;
    dynamic bestContour;

    for (final contour in contours) {
      final area = cv.contourArea(contour);

      if (area > largestArea) {
        largestArea = area;
        bestContour = contour;
      }
    }

    if (bestContour == null) {
      return null;
    }

    /*
     * Find minimum rotated rectangle.
     *
     * This allows the object to be rotated.
     */
    final rotatedRect =
    cv.minAreaRect(bestContour);

    /*
     * In opencv_dart, RotatedRect exposes
     * the rectangle size.
     */
    final rectWidth =
    rotatedRect.size.width.toDouble();

    final rectHeight =
    rotatedRect.size.height.toDouble();

    /*
     * Always treat the larger dimension as
     * length and smaller as width.
     */
    final lengthPx =
    rectWidth >= rectHeight
        ? rectWidth
        : rectHeight;

    final widthPx =
    rectWidth >= rectHeight
        ? rectHeight
        : rectWidth;

    return DetectedPartDimensions(
      lengthPx: lengthPx,
      widthPx: widthPx,
    );
  }
}