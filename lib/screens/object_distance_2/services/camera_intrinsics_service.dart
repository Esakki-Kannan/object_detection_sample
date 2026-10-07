import 'package:flutter/services.dart';

import '../models/camera_intrinsics.dart';


class CameraIntrinsicsService {
  static const MethodChannel _channel =
  MethodChannel('camera_intrinsics');

  static Future<CameraIntrinsics> getIntrinsics({
    required String cameraId,
  }) async {
    final result =
    await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getCameraIntrinsics',
      {
        'cameraId': cameraId,
      },
    );

    if (result == null) {
      throw Exception(
        'Camera intrinsics could not be obtained.',
      );
    }

    return CameraIntrinsics.fromMap(result);
  }
}