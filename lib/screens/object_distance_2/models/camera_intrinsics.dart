class CameraIntrinsics {
  final double focalLengthMm;

  final double sensorWidthMm;
  final double sensorHeightMm;

  final double sensorWidthPx;
  final double sensorHeightPx;

  final double fx;
  final double fy;

  final double cx;
  final double cy;

  const CameraIntrinsics({
    required this.focalLengthMm,
    required this.sensorWidthMm,
    required this.sensorHeightMm,
    required this.sensorWidthPx,
    required this.sensorHeightPx,
    required this.fx,
    required this.fy,
    required this.cx,
    required this.cy,
  });

  factory CameraIntrinsics.fromMap(
      Map<dynamic, dynamic> map,
      ) {
    return CameraIntrinsics(
      focalLengthMm:
      (map['focalLengthMm'] as num).toDouble(),

      sensorWidthMm:
      (map['sensorWidthMm'] as num).toDouble(),

      sensorHeightMm:
      (map['sensorHeightMm'] as num).toDouble(),

      sensorWidthPx:
      (map['sensorWidthPx'] as num).toDouble(),

      sensorHeightPx:
      (map['sensorHeightPx'] as num).toDouble(),

      fx:
      (map['fx'] as num).toDouble(),

      fy:
      (map['fy'] as num).toDouble(),

      cx:
      (map['cx'] as num).toDouble(),

      cy:
      (map['cy'] as num).toDouble(),
    );
  }

  CameraIntrinsics scaleToImageSize({
    required double imageWidthPx,
    required double imageHeightPx,
  }) {
    final scaleX = imageWidthPx / sensorWidthPx;
    final scaleY = imageHeightPx / sensorHeightPx;
    return CameraIntrinsics(
      focalLengthMm: focalLengthMm,
      sensorWidthMm: sensorWidthMm,
      sensorHeightMm: sensorHeightMm,
      sensorWidthPx: imageWidthPx,
      sensorHeightPx: imageHeightPx,
      fx: fx * scaleX,
      fy: fy * scaleY,
      cx: cx * scaleX,
      cy: cy * scaleY,
    );
  }
}