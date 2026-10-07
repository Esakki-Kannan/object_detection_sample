import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:opencv_dart/opencv.dart' as cv;
import 'package:product_matcher/screens/object_distance_2/services/distance_calculator.dart';







import '../models/camera_intrinsics.dart';
import '../models/part_dimensions.dart';
import 'camera_intrinsics_service.dart';
import 'opencv_part_detector.dart';

class DistanceMeasureScreen extends StatefulWidget {
  const DistanceMeasureScreen({
    super.key,
  });

  @override
  State<DistanceMeasureScreen> createState() =>
      _DistanceMeasureScreenState();
}

class _DistanceMeasureScreenState
    extends State<DistanceMeasureScreen> {

  CameraController? _cameraController;

  CameraIntrinsics? _intrinsics;

  bool _initializing = true;
  bool _processing = false;

  final _lengthController =
  TextEditingController();

  final _widthController =
  TextEditingController();

  String _result = 'Distance: --';

  String _cameraInfo = '';

  @override
  void initState() {
    super.initState();

    _initialize();
  }
  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw Exception('No camera found.');
      }

      final backCamera = cameras.firstWhere(
            (camera) =>
        camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      debugPrint(
        'Selected camera ID: ${backCamera.name}',
      );

      final controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
      );

      await controller.initialize();

      debugPrint(
        'Camera initialized successfully: '
            '${controller.value.previewSize}',
      );

      if (!mounted) {
        await controller.dispose();
        return;
      }

      // IMPORTANT:
      // Show the camera immediately.
      setState(() {
        _cameraController = controller;
        _initializing = false;
        _result = 'Camera ready';
      });

      // Get intrinsics AFTER camera is already visible.
      try {
        debugPrint(
          'Getting camera intrinsics for ID: '
              '${backCamera.name}',
        );

        final intrinsics =
        await CameraIntrinsicsService.getIntrinsics(
          cameraId: backCamera.name,
        );

        debugPrint(
          'Camera intrinsics received: $intrinsics',
        );

        if (!mounted) return;

        setState(() {
          _intrinsics = intrinsics;

          _cameraInfo =
          'Focal length: '
              '${intrinsics.focalLengthMm.toStringAsFixed(2)} mm\n'
              'fx: '
              '${intrinsics.fx.toStringAsFixed(1)} px\n'
              'fy: '
              '${intrinsics.fy.toStringAsFixed(1)} px';
        });
      } catch (e, stackTrace) {
        debugPrint(
          'INTRINSICS ERROR: $e',
        );

        debugPrint(
          stackTrace.toString(),
        );

        if (!mounted) return;

        setState(() {
          _cameraInfo =
          'Camera ready\n'
              'Intrinsics error: $e';

          _result =
          'Camera opened, but camera information '
              'could not be read.';
        });
      }
    } catch (e, stackTrace) {
      debugPrint(
        'CAMERA INITIALIZATION ERROR: $e',
      );

      debugPrint(
        stackTrace.toString(),
      );

      if (!mounted) return;

      setState(() {
        _initializing = false;
        _result =
        'Camera initialization error:\n$e';
      });
    }
  }

  // Future<void> _initialize() async {
  //   try {
  //     final cameras =
  //     await availableCameras();
  //
  //     if (cameras.isEmpty) {
  //       throw Exception(
  //         'No camera found.',
  //       );
  //     }
  //
  //     final backCamera =
  //     cameras.firstWhere(
  //           (camera) =>
  //       camera.lensDirection ==
  //           CameraLensDirection.back,
  //       orElse: () => cameras.first,
  //     );
  //
  //     final controller =
  //     CameraController(
  //       backCamera,
  //       ResolutionPreset.high,
  //       enableAudio: false,
  //     );
  //
  //     await controller.initialize();
  //
  //     final intrinsics =
  //     await CameraIntrinsicsService
  //         .getIntrinsics(
  //       cameraId: backCamera.name,
  //     );
  //
  //     if (!mounted) {
  //       await controller.dispose();
  //       return;
  //     }
  //
  //     setState(() {
  //       _camera = backCamera;
  //       _cameraController = controller;
  //       _intrinsics = intrinsics;
  //
  //       _cameraInfo =
  //       'Focal length: '
  //           '${intrinsics.focalLengthMm.toStringAsFixed(2)} mm\n'
  //           'fx: '
  //           '${intrinsics.fx.toStringAsFixed(1)} px\n'
  //           'fy: '
  //           '${intrinsics.fy.toStringAsFixed(1)} px';
  //
  //       _initializing = false;
  //     });
  //   } catch (e) {
  //     if (!mounted) return;
  //
  //     setState(() {
  //       _initializing = false;
  //       _result = 'Initialization error:\n$e';
  //     });
  //   }
  // }

  Future<void> _measureDistance() async {
    if (_processing) {
      return;
    }

    final controller =
        _cameraController;

    final intrinsics =
        _intrinsics;

    if (controller == null ||
        !controller.value.isInitialized ||
        intrinsics == null) {
      return;
    }

    final lengthCm =
    double.tryParse(
      _lengthController.text.trim(),
    );

    final widthCm =
    double.tryParse(
      _widthController.text.trim(),
    );

    if (lengthCm == null ||
        widthCm == null ||
        lengthCm <= 0 ||
        widthCm <= 0) {

      setState(() {
        _result =
        'Enter valid length and width.';
      });

      return;
    }

    setState(() {
      _processing = true;
      _result = 'Capturing...';
    });

    try {
      /*
       * Capture image.
       */
      final image =
      await controller.takePicture();

      /*
       * Read image bytes.
       */
      final imageBytes =
      await image.readAsBytes();

      setState(() {
        _result =
        'Detecting object...';
      });

      /*
       * OpenCV object detection.
       */
      final detected =
      await OpenCvPartDetector.detect(
        imageBytes,
      );

      if (detected == null) {
        setState(() {
          _result =
          'Object could not be detected.';
        });

        return;
      }

      /*
       * Real-world dimensions.
       */
      final dimensions =
      PartDimensions(
        lengthCm: lengthCm,
        widthCm: widthCm,
      );

      /*
       * Calculate distance.
       */
      // Decode to get dimensions using OpenCV (or image package)
      // We have bytes; decode quickly
      final decoded = cv.imdecode(imageBytes, cv.IMREAD_COLOR);
      final scaledIntrinsics = intrinsics.scaleToImageSize(
        imageWidthPx: decoded.cols.toDouble(),
        imageHeightPx: decoded.rows.toDouble(),
      );
      final distance =
      DistanceCalculator.calculate(
        realDimensions: dimensions,
        detectedLengthPx:
        detected.lengthPx,
        detectedWidthPx:
        detected.widthPx,
        intrinsics: scaledIntrinsics,
      );

      if (!mounted) return;

      setState(() {
        _result =
        'Distance: '
            '${distance.finalDistanceCm.toStringAsFixed(2)} cm\n\n'
            'From length: '
            '${distance.distanceFromLengthCm.toStringAsFixed(2)} cm\n'
            'From width: '
            '${distance.distanceFromWidthCm.toStringAsFixed(2)} cm\n\n'
            'Detected length: '
            '${detected.lengthPx.toStringAsFixed(1)} px\n'
            'Detected width: '
            '${detected.widthPx.toStringAsFixed(1)} px';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _result =
        'Measurement error:\n$e';
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

    _lengthController.dispose();
    _widthController.dispose();

    super.dispose();
  }

  @override
  Widget build(
      BuildContext context,
      ) {
    if (_initializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final controller =
        _cameraController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return Scaffold(
        body: Center(
          child: Text('res $_result'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Object Distance',
        ),
      ),
      body: Column(
        children: [

          /*
           * Camera preview
           */
          Expanded(
            child: CameraPreview(
              controller,
            ),
          ),

          /*
           * Camera information
           */
          Padding(
            padding:
            const EdgeInsets.all(8),
            child: Text(
              _cameraInfo,
              textAlign: TextAlign.center,
            ),
          ),

          /*
           * Real length
           */
          Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            child: TextField(
              controller:
              _lengthController,
              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
              const InputDecoration(
                labelText:
                'Real Length (cm)',
                border:
                OutlineInputBorder(),
              ),
            ),
          ),

          /*
           * Real width
           */
          Padding(
            padding:
            const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 4,
            ),
            child: TextField(
              controller:
              _widthController,
              keyboardType:
              const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration:
              const InputDecoration(
                labelText:
                'Real Width (cm)',
                border:
                OutlineInputBorder(),
              ),
            ),
          ),

          /*
           * Result
           */
          Padding(
            padding:
            const EdgeInsets.all(12),
            child: Text(
              _result,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 18,
                fontWeight:
                FontWeight.bold,
              ),
            ),
          ),

          /*
           * Measure button
           */
          Padding(
            padding:
            const EdgeInsets.fromLTRB(
              16,
              0,
              16,
              16,
            ),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _processing
                    ? null
                    : _measureDistance,
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