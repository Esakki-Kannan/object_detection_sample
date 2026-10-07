package com.example.product_matcher

import android.content.Context
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.util.Size
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.math.PI
import kotlin.math.tan

class MainActivity : FlutterActivity() {

    private val CHANNEL = "camera_intrinsics"

    override fun configureFlutterEngine(
        flutterEngine: FlutterEngine
    ) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->

            when (call.method) {

                "getCameraIntrinsics" -> {

                    val cameraId =
                        call.argument<String>("cameraId")

                    if (cameraId == null) {
                        result.error(
                            "INVALID_CAMERA",
                            "Camera ID is missing",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    try {

                        val intrinsics =
                            getCameraIntrinsics(cameraId)

                        result.success(intrinsics)

                    } catch (e: Exception) {

                        result.error(
                            "CAMERA_INTRINSICS_ERROR",
                            e.message,
                            null
                        )
                    }
                }

                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    private fun getCameraIntrinsics(
        cameraId: String
    ): Map<String, Any> {

        val cameraManager =
            getSystemService(Context.CAMERA_SERVICE) as CameraManager

        // Flutter camera plugin may return values such as:
        // "Camera 0"
        // "Camera 1"
        //
        // Android Camera2 expects:
        // "0"
        // "1"

        val androidCameraId = cameraId
            .removePrefix("Camera ")
            .trim()

        android.util.Log.d(
            "CameraIntrinsics",
            "Flutter camera ID = $cameraId"
        )

        android.util.Log.d(
            "CameraIntrinsics",
            "Android camera ID = $androidCameraId"
        )

        val cameraIds = cameraManager.cameraIdList

        android.util.Log.d(
            "CameraIntrinsics",
            "Available Android camera IDs = ${cameraIds.joinToString()}"
        )

        if (!cameraIds.contains(androidCameraId)) {
            throw Exception(
                "Camera ID $androidCameraId is not available. " +
                        "Available IDs: ${cameraIds.joinToString()}"
            )
        }

        val characteristics =
            cameraManager.getCameraCharacteristics(
                androidCameraId
            )

        // Keep the rest of your existing code below this point.

        val focalLengths =
            characteristics.get(
                CameraCharacteristics
                    .LENS_INFO_AVAILABLE_FOCAL_LENGTHS
            )

        val sensorPhysicalSize =
            characteristics.get(
                CameraCharacteristics
                    .SENSOR_INFO_PHYSICAL_SIZE
            )

        val sensorPixelArraySize =
            characteristics.get(
                CameraCharacteristics
                    .SENSOR_INFO_PIXEL_ARRAY_SIZE
            )

        android.util.Log.d(
            "CameraIntrinsics",
            "focalLengths = ${focalLengths?.contentToString()}"
        )

        android.util.Log.d(
            "CameraIntrinsics",
            "sensorPhysicalSize = $sensorPhysicalSize"
        )

        android.util.Log.d(
            "CameraIntrinsics",
            "sensorPixelArraySize = $sensorPixelArraySize"
        )

        if (
            focalLengths == null ||
            focalLengths.isEmpty()
        ) {
            throw Exception(
                "LENS_INFO_AVAILABLE_FOCAL_LENGTHS is unavailable."
            )
        }

        if (sensorPhysicalSize == null) {
            throw Exception(
                "SENSOR_INFO_PHYSICAL_SIZE is unavailable."
            )
        }

        if (sensorPixelArraySize == null) {
            throw Exception(
                "SENSOR_INFO_PIXEL_ARRAY_SIZE is unavailable."
            )
        }

        val focalLengthMm =
            focalLengths[0].toDouble()

        val sensorWidthMm =
            sensorPhysicalSize.width.toDouble()

        val sensorHeightMm =
            sensorPhysicalSize.height.toDouble()

        val sensorWidthPx =
            sensorPixelArraySize.width.toDouble()

        val sensorHeightPx =
            sensorPixelArraySize.height.toDouble()

        val fx =
            (focalLengthMm / sensorWidthMm) *
                    sensorWidthPx

        val fy =
            (focalLengthMm / sensorHeightMm) *
                    sensorHeightPx

        val cx =
            sensorWidthPx / 2.0

        val cy =
            sensorHeightPx / 2.0

        android.util.Log.d(
            "CameraIntrinsics",
            "focalLengthMm = $focalLengthMm"
        )

        android.util.Log.d(
            "CameraIntrinsics",
            "fx = $fx"
        )

        android.util.Log.d(
            "CameraIntrinsics",
            "fy = $fy"
        )

        return mapOf(
            "focalLengthMm" to focalLengthMm,

            "sensorWidthMm" to sensorWidthMm,
            "sensorHeightMm" to sensorHeightMm,

            "sensorWidthPx" to sensorWidthPx,
            "sensorHeightPx" to sensorHeightPx,

            "fx" to fx,
            "fy" to fy,

            "cx" to cx,
            "cy" to cy
        )
    }

//    private fun getCameraIntrinsics(
//        cameraId: String
//    ): Map<String, Any> {
//
//        val cameraManager =
//            getSystemService(
//                Context.CAMERA_SERVICE
//            ) as CameraManager
//
//        val characteristics =
//            cameraManager.getCameraCharacteristics(cameraId)
//
//        val focalLengths =
//            characteristics.get(
//                CameraCharacteristics
//                    .LENS_INFO_AVAILABLE_FOCAL_LENGTHS
//            )
//
//        val sensorPhysicalSize =
//            characteristics.get(
//                CameraCharacteristics
//                    .SENSOR_INFO_PHYSICAL_SIZE
//            )
//
//        val sensorPixelArraySize =
//            characteristics.get(
//                CameraCharacteristics
//                    .SENSOR_INFO_PIXEL_ARRAY_SIZE
//            )
//
//        if (
//            focalLengths == null ||
//            focalLengths.isEmpty()
//        ) {
//            throw Exception(
//                "Camera does not provide focal length"
//            )
//        }
//
//        if (sensorPhysicalSize == null) {
//            throw Exception(
//                "Camera does not provide sensor physical size"
//            )
//        }
//
//        if (sensorPixelArraySize == null) {
//            throw Exception(
//                "Camera does not provide sensor pixel size"
//            )
//        }
//
//        // First available focal length.
//        //
//        // Units: millimeters.
//        val focalLengthMm =
//            focalLengths[0].toDouble()
//
//        val sensorWidthMm =
//            sensorPhysicalSize.width.toDouble()
//
//        val sensorHeightMm =
//            sensorPhysicalSize.height.toDouble()
//
//        val sensorWidthPx =
//            sensorPixelArraySize.width.toDouble()
//
//        val sensorHeightPx =
//            sensorPixelArraySize.height.toDouble()
//
//        /*
//         * Convert physical focal length to
//         * focal length in pixels.
//         *
//         * fx = focalLength(mm) / sensorWidth(mm)
//         *      * sensorWidth(pixel)
//         */
//        val fx =
//            (focalLengthMm / sensorWidthMm) *
//                    sensorWidthPx
//
//        val fy =
//            (focalLengthMm / sensorHeightMm) *
//                    sensorHeightPx
//
//        val cx =
//            sensorWidthPx / 2.0
//
//        val cy =
//            sensorHeightPx / 2.0
//
//        return mapOf(
//            "focalLengthMm" to focalLengthMm,
//            "sensorWidthMm" to sensorWidthMm,
//            "sensorHeightMm" to sensorHeightMm,
//            "sensorWidthPx" to sensorWidthPx,
//            "sensorHeightPx" to sensorHeightPx,
//            "fx" to fx,
//            "fy" to fy,
//            "cx" to cx,
//            "cy" to cy
//        )
//    }
}