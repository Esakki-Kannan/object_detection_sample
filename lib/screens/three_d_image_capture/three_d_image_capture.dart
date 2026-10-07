import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class MultiAngleCaptureScreen extends StatefulWidget {
  const MultiAngleCaptureScreen({
    super.key,
    required this.cameras,
  });

  final List<CameraDescription> cameras;

  @override
  State<MultiAngleCaptureScreen> createState() =>
      _MultiAngleCaptureScreenState();
}

class _MultiAngleCaptureScreenState
    extends State<MultiAngleCaptureScreen> {
  CameraController? _cameraController;

  final List<File> _capturedImages = [];

  bool _isInitializing = true;
  bool _isCapturing = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      return;
    }

    final camera = widget.cameras.firstWhere(
          (camera) => camera.lensDirection == CameraLensDirection.back,
      orElse: () => widget.cameras.first,
    );

    final controller = CameraController(
      camera,
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
      _isInitializing = false;
    });
  }

  Future<void> _captureImage() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isCapturing) {
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile image = await controller.takePicture();

      final directory = await getApplicationDocumentsDirectory();

      final captureDirectory = Directory(
        path.join(directory.path, 'part_capture'),
      );

      if (!await captureDirectory.exists()) {
        await captureDirectory.create(recursive: true);
      }

      final fileName =
          'view_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final savedFile = File(
        path.join(captureDirectory.path, fileName),
      );

      await File(image.path).copy(savedFile.path);

      if (!mounted) return;

      setState(() {
        _capturedImages.add(savedFile);
      });
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture image: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  void _removeImage(int index) {
    setState(() {
      _capturedImages.removeAt(index);
    });
  }

  void _finishCapture() {
    if (_capturedImages.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Capture at least 4 different views of the part.',
          ),
        ),
      );

      return;
    }

    Navigator.pop(
      context,
      _capturedImages,
    );
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return const Scaffold(
        body: Center(
          child: Text('Camera initialization failed'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capture Part'),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 6,
            child: CameraPreview(controller),
          ),

          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Capture the part from different angles',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          SizedBox(
            height: 100,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
              ),
              itemCount: _capturedImages.length,
              itemBuilder: (context, index) {
                final image = _capturedImages[index];

                return Stack(
                  children: [
                    Container(
                      width: 90,
                      height: 90,
                      margin: const EdgeInsets.only(
                        right: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: FileImage(image),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                    Positioned(
                      right: 12,
                      top: 2,
                      child: GestureDetector(
                        onTap: () => _removeImage(index),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(
                            color: Colors.red,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 12),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              Text(
                '${_capturedImages.length} images',
              ),

              FloatingActionButton(
                onPressed:
                _isCapturing ? null : _captureImage,
                child: _isCapturing
                    ? const CircularProgressIndicator(
                  color: Colors.white,
                )
                    : const Icon(Icons.camera_alt),
              ),

              ElevatedButton(
                onPressed: _capturedImages.length >= 4
                    ? _finishCapture
                    : null,
                child: const Text('Create 3D'),
              ),
            ],
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}