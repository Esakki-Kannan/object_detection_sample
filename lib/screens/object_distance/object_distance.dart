import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import 'distance_calculator.dart';
import 'opencv_object_detector.dart';

class DistanceCameraScreen extends StatefulWidget {
  const DistanceCameraScreen({
    super.key,
  });

  @override
  State<DistanceCameraScreen> createState() =>
      _DistanceCameraScreenState();
}

class _DistanceCameraScreenState
    extends State<DistanceCameraScreen> {

  CameraController? _cameraController;

  bool _initializing = true;
  bool _processing = false;

  String _distanceText = 'Distance: --';

  // ------------------------------------------------------------
  // CHANGE THESE VALUES FOR YOUR PART
  // ------------------------------------------------------------

  // Example mechanical part:
  // Real-world width = 50 mm
  static const double realObjectWidthMm = 50.0;

  // This value comes from camera calibration.
  // Example only.
  static const double focalLengthPx = 1200.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    final cameras = await availableCameras();

    final backCamera = cameras.firstWhere(
          (camera) =>
      camera.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );

    final controller = CameraController(
      backCamera,
      ResolutionPreset.high,
      enableAudio: false,
    );

    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    setState(() {
      _cameraController = controller;
      _initializing = false;
    });
  }

  Future<void> _captureAndCalculateDistance() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _processing) {
      return;
    }

    setState(() {
      _processing = true;
      _distanceText = 'Processing...';
    });

    try {
      final XFile image = await controller.takePicture();

      final imageBytes = await image.readAsBytes();

      final detectedSize =
      await OpenCvObjectDetector.detectObject(
        imageBytes,
      );

      if (detectedSize == null) {
        if (!mounted) return;

        setState(() {
          _distanceText = 'Object not detected';
        });

        return;
      }

      final distanceMm =
      DistanceCalculator.calculateDistance(
        realWidthMm: realObjectWidthMm,
        focalLengthPx: focalLengthPx,
        imageWidthPx: detectedSize.widthPx,
      );

      if (!mounted) return;

      setState(() {
        _distanceText =
        'Distance: ${distanceMm.toStringAsFixed(1)} mm\n'
            'Object width: '
            '${detectedSize.widthPx.toStringAsFixed(1)} px';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _distanceText = 'Error: $e';
      });
    } finally {
      if (!mounted) return;

      setState(() {
        _processing = false;
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_initializing ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Object Distance'),
      ),
      body: Column(
        children: [
          Expanded(
            child: CameraPreview(
              _cameraController!,
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              _distanceText,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _processing
                    ? null
                    : _captureAndCalculateDistance,
                child: Text(
                  _processing
                      ? 'Processing...'
                      : 'Measure Distance',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}