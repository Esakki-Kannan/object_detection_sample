import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';

class ThreeDViewScreen extends StatelessWidget {
  const ThreeDViewScreen({
    super.key,
    required this.modelPath,
  });

  final String modelPath;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('3D Part'),
      ),
      body: ModelViewer(
        src: modelPath,
        alt: 'Mechanical part 3D model',

        cameraControls: true,

        autoRotate: true,

        disableZoom: false,

        backgroundColor: Colors.white,
      ),
    );
  }
}