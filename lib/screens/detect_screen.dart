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
  final FeatureMatch? match;
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

  /// How strongly the ORB feature score matters vs dimensions (0..1).
  double _orbWeight = 0.6;
  bool _showGrid = true;

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
        obj.orbDescriptors,
        _tolerance,
        _orbWeight,
        inputMatrix: obj.matrix,
      );
      obj.label = match?.name;
      obj.matchDistance = match?.combinedScore;
      uiList.add(_ObjectUi(obj, match));
    }

    // Reuse the objects just matched on instead of running detection a second
    // time for the drawing step.
    final annotated = objects.isEmpty
        ? null
        : OpenCVService.annotateObjects(bytes, objects, showGrid: _showGrid);

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
              const Text('ORB:'),
              Expanded(
                child: Slider(
                  value: _orbWeight,
                  min: 0,
                  max: 1,
                  divisions: 10,
                  label: _orbWeight.toStringAsFixed(1),
                  onChanged: _processing
                      ? null
                      : (v) {
                          setState(() => _orbWeight = v);
                          if (_objects.isNotEmpty) _detect();
                        },
                ),
              ),
              Text(_orbWeight.toStringAsFixed(1)),
            ],
          ),
          SwitchListTile(
            title: const Text('Show grid'),
            value: _showGrid,
            onChanged: (v) {
              setState(() => _showGrid = v);
              if (_objects.isNotEmpty) _detect();
            },
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
              // Grid preview(s) below detected image
              Text('Shape matrix (64×64, white=body, black=hole/bg)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _objects.map((ui) {
                  final gridBytes = ui.obj.matrix != null
                      ? OpenCVService.matrixToGridImage(ui.obj.matrix!, label: ui.obj.label ?? 'no match')
                      : null;
                  return gridBytes == null
                      ? const SizedBox()
                      : Column(
                          children: [
                            Image.memory(gridBytes, width: 140, height: 150, fit: BoxFit.contain),
                            const SizedBox(height: 4),
                            Text('${ui.obj.width}×${ui.obj.height}', style: const TextStyle(fontSize: 11)),
                          ],
                        );
                }).toList(),
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
                final features = ui.obj.hasOrbDescriptors
                    ? 'ORB match'
                    : match != null && match.featureScore > 0
                        ? 'Matrix match'
                        : 'no features';
                return Card(
                  child: ListTile(
                    leading: matched != null
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.cancel, color: Colors.red),
                    title: Text(matched ?? 'No match'),
                    subtitle: Text(
                      'Size: ${ui.obj.width} x ${ui.obj.height} px'
                      '${match != null ? '\nSize diff: ${match.dimensionScore.toStringAsFixed(1)}%  '
                          '$features: ${(match.featureScore * 100).toStringAsFixed(0)}%  '
                          'ORB keypoints: ${ui.obj.orbDescriptorCount}' : ''}',
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
