class DistanceResult {
  final double distanceMm;
  final double detectedWidthPx;
  final double detectedHeightPx;

  const DistanceResult({
    required this.distanceMm,
    required this.detectedWidthPx,
    required this.detectedHeightPx,
  });
}

class DistanceCalculator {
  /// Calculates distance using:
  ///
  /// distance = (realWidth * focalLengthPx) / imageWidthPx
  ///
  /// All dimensions must use the same physical unit.
  static double calculateDistance({
    required double realWidthMm,
    required double focalLengthPx,
    required double imageWidthPx,
  }) {
    if (realWidthMm <= 0) {
      throw ArgumentError('realWidthMm must be greater than zero');
    }

    if (focalLengthPx <= 0) {
      throw ArgumentError('focalLengthPx must be greater than zero');
    }

    if (imageWidthPx <= 0) {
      throw ArgumentError('imageWidthPx must be greater than zero');
    }

    return (realWidthMm * focalLengthPx) / imageWidthPx;
  }
}