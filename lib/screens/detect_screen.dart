import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../matcher.dart';
import '../opencv_service.dart';
import '../product_db.dart';

class _ObjectUi {
  final DetectedObject obj;
  final MatrixMatch? match;
  _ObjectUi(this.obj, this.match);
}

class DetectScreen extends StatefulWidget {
  final ProductDb db;
  const DetectScreen({super.key, required this.db});

  @override
  State<DetectScreen> createState() => _DetectScreenState();
}

class _DetectScreenState extends State<DetectScreen> {
  XFile? _image;
  List<_ObjectUi> _objects = [];
  Uint8List? _annotated;
  bool _processing = false;
  double _tolerance = 10;
  bool _noGreen = false;

  /// How strongly the internal matrix matters vs dimensions (0..1).
  double _matrixWeight = 0.6;

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, maxWidth: 2048, maxHeight: 2048);
    if (file == null) return;
    setState(() {
      _image = file;
      _objects = [];
      _annotated = null;
      _noGreen = false;
    });
    _detect();
  }

  Future<void> _detect() async {
    if (_image == null) return;
    setState(() {
      _processing = true;
      _objects = [];
      _annotated = null;
      _noGreen = false;
    });
    final bytes = await _image!.readAsBytes();
    final objects = OpenCVService.detectGreenObjectsBytes(bytes);
    final products = widget.db.products.values.toList();

    final uiList = <_ObjectUi>[];
    for (final obj in objects) {
      final match = ProductMatcher.matchObject(
        products,
        obj.width,
        obj.height,
        obj.matrix,
        _tolerance,
        _matrixWeight,
      );
      obj.label = match?.name;
      obj.matchDistance = match?.combinedScore;
      uiList.add(_ObjectUi(obj, match));
    }

    Uint8List? annotated;
    if (objects.isNotEmpty) {
      annotated = OpenCVService.drawAnnotatedBytes(bytes, objects.map((o) => o.label).toList());
    }

    setState(() {
      _objects = uiList;
      _annotated = annotated;
      _noGreen = objects.isEmpty;
      _processing = false;
    });
  }

  Future<void> _saveOutput() async {
    final annotated = _annotated;
    if (annotated == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final ts = DateTime.now().millisecondsSinceEpoch;
      final file = File('${dir.path}/detected_$ts.jpg');
      await file.writeAsBytes(annotated);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved to ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Detect Products')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Pick an image to detect all green objects',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _processing ? null : () => _pickImage(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _processing ? null : () => _pickImage(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(_image!.path), height: 200, fit: BoxFit.cover),
            ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Tolerance:'),
              Expanded(
                child: Slider(
                  value: _tolerance,
                  min: 1,
                  max: 30,
                  divisions: 29,
                  label: '${_tolerance.toStringAsFixed(0)}%',
                  onChanged: _processing
                      ? null
                      : (v) {
                          setState(() => _tolerance = v);
                          if (_objects.isNotEmpty) _detect();
                        },
                ),
              ),
              Text('${_tolerance.toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Matrix:'),
              Expanded(
                child: Slider(
                  value: _matrixWeight,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  label: _matrixWeight.toStringAsFixed(1),
                  onChanged: _processing
                      ? null
                      : (v) {
                          setState(() => _matrixWeight = v);
                          if (_objects.isNotEmpty) _detect();
                        },
                ),
              ),
              Text(_matrixWeight.toStringAsFixed(1)),
            ],
          ),
          const SizedBox(height: 8),
          if (_processing)
            const Center(child: CircularProgressIndicator())
          else if (_noGreen)
            const Text('No green objects detected in the image.')
          else if (_objects.isNotEmpty) ...[
            if (_annotated != null) ...[
              Text('Detection Output (${_objects.length} object(s))',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(_annotated!, height: 260, fit: BoxFit.cover),
              ),
              const SizedBox(height: 8),
              IconButton(
                icon: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [Icon(Icons.download), SizedBox(width: 4), Text('Save output')],
                ),
                onPressed: _saveOutput,
              ),
              const Divider(height: 32),
              Text('Per-object match', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              ..._objects.map((ui) {
                final match = ui.match;
                final matched = match?.name;
                return Card(
                  child: ListTile(
                    leading: matched != null
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.cancel, color: Colors.red),
                    title: Text(matched ?? 'No match'),
                    subtitle: Text(
                      'Size: ${ui.obj.width} x ${ui.obj.height} px'
                      '${match != null ? '\nSize diff: ${match.dimensionScore.toStringAsFixed(1)}%  '
                          'Matrix diff: ${(match.matrixScore * 100).toStringAsFixed(1)}%' : ''}',
                    ),
                  ),
                );
              }),
            ] else
              const Text('Analyzing...'),
          ] else if (_image == null)
            const Text('Select an image to begin.'),
        ],
      ),
    );
  }
}
