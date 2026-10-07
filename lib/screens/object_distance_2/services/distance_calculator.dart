import '../models/camera_intrinsics.dart';
import '../models/part_dimensions.dart';

class DistanceResult {
  final double distanceFromLengthCm;
  final double distanceFromWidthCm;
  final double finalDistanceCm;

  const DistanceResult({
    required this.distanceFromLengthCm,
    required this.distanceFromWidthCm,
    required this.finalDistanceCm,
  });
}

class DistanceCalculator {
  static DistanceResult calculate({
    required PartDimensions realDimensions,
    required double detectedLengthPx,
    required double detectedWidthPx,
    required CameraIntrinsics intrinsics,
  }) {
    if (detectedLengthPx <= 0) {
      throw Exception(
        'Detected length is invalid.',
      );
    }

    if (detectedWidthPx <= 0) {
      throw Exception(
        'Detected width is invalid.',
      );
    }

    /*
     * Pinhole camera model:
     *
     * Z = realSize * focalLengthPx / imageSizePx
     */

    // Use average focal length to avoid axis/orientation mismatches
    final focalPx = (intrinsics.fx + intrinsics.fy) / 2.0;

    final distanceFromLengthCm =
        (realDimensions.lengthCm * focalPx) /
            detectedLengthPx;

    final distanceFromWidthCm =
        (realDimensions.widthCm * focalPx) /
            detectedWidthPx;

    /*
     * For a front-facing planar object,
     * both values should be approximately equal.
     */

    final finalDistanceCm =
        (distanceFromLengthCm +
            distanceFromWidthCm) /
            2.0;

    return DistanceResult(
      distanceFromLengthCm:
      distanceFromLengthCm,
      distanceFromWidthCm:
      distanceFromWidthCm,
      finalDistanceCm:
      finalDistanceCm,
    );
  }
}