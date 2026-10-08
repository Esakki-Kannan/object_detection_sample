package com.example.product_matcher

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "camera_info")
            .setMethodCallHandler { call, result ->
                if (call.method == "getCameraInfo") {
                    try {
                        val wantFront = call.argument<Boolean>("front") ?: false
                        val wanted = if (wantFront) CameraCharacteristics.LENS_FACING_FRONT
                        else CameraCharacteristics.LENS_FACING_BACK

                        val manager = getSystemService(Context.CAMERA_SERVICE) as CameraManager

                        // first camera facing the wanted direction (usually id "0" for back)
                        val id = manager.cameraIdList.firstOrNull { cid ->
                            manager.getCameraCharacteristics(cid)
                                .get(CameraCharacteristics.LENS_FACING) == wanted
                        } ?: throw Exception("No camera with requested facing")

                        val c = manager.getCameraCharacteristics(id)
                        val focal = c.get(CameraCharacteristics.LENS_INFO_AVAILABLE_FOCAL_LENGTHS)!![0]
                        val size = c.get(CameraCharacteristics.SENSOR_INFO_PHYSICAL_SIZE)!!

                        result.success(mapOf(
                            "cameraId" to id,
                            "focalMm" to focal.toDouble(),
                            "sensorW" to size.width.toDouble(),
                            "sensorH" to size.height.toDouble()
                        ))
                    } catch (e: Exception) {
                        result.error("CAMERA_INFO_ERROR", e.message, null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}