import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../matcher.dart';
import '../opencv_service.dart';
import '../product_db.dart';

class ProductVerifyScreen extends StatefulWidget {
  final ProductDb db;
  final String productName;
  const ProductVerifyScreen({super.key, required this.db, required this.productName});

  @override
  State<ProductVerifyScreen> createState() => _ProductVerifyScreenState();
}

class _ProductVerifyScreenState extends State<ProductVerifyScreen> {
  XFile? _image;
  Uint8List? _annotated;
  List<DetectedObject> _objects = [];
  bool _processing = false;

  /// null = not checked, true/false after a check.
  bool? _matched;

  double _tolerance = 10;
  double _orbWeight = 0.6;
  bool _showGrid = true;

  Future<void> _pick(ImageSource src) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: src, maxWidth: 2048, maxHeight: 2048);
    if (file == null) return;
    setState(() {
      _image = file;
      _annotated = null;
      _objects = [];
      _matched = null;
    });
    await _check();
  }

  Future<void> _check() async {
    if (_image == null) return;
    setState(() => _processing = true);
    final bytes = await _image!.readAsBytes();
    final objects = OpenCVService.detectGreenObjectsBytes(bytes);
    final product = widget.db.products[widget.productName];

    if (product == null || objects.isEmpty) {
      if (!mounted) return;
      setState(() {
        _matched = false;
        _objects = objects;
        _annotated = null;
        _processing = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Part Not matched'), backgroundColor: Colors.red),
      );
      return;
    }

    var anyMatch = false;
    for (final obj in objects) {
      // Match against this single product only; the feature pass carries the
      // ORB descriptors extracted from the photo and the stored reference.
      final m = ProductMatcher.matchObject(
        [product],
        obj.width,
        obj.height,
        obj.orbDescriptors,
        _tolerance,
        _orbWeight,
        inputMatrix: obj.matrix,
      );
      if (m != null) {
        anyMatch = true;
        obj.label = product.name;
        obj.matchDistance = m.combinedScore;
        break;
      }
    }

    // Reuse the matched objects for drawing so no second detection pass runs.
    final annotated = OpenCVService.annotateObjects(bytes, objects, showGrid: _showGrid);
    if (anyMatch) {
      await widget.db.markVerified(widget.productName);
    }

    if (!mounted) return;
    setState(() {
      _objects = objects;
      _matched = anyMatch;
      _annotated = annotated;
      _processing = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            anyMatch ? 'Part detected successfully: ${widget.productName}' : 'Part Not matched'),
        backgroundColor: anyMatch ? Colors.green : Colors.red,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: _matched == true
          ? FloatingActionButton(
              onPressed: () {
                Navigator.of(context).pop(true);
              },
              backgroundColor: Colors.green,
              child: const Icon(Icons.check),
            )
          : null,
      appBar: AppBar(title: Text('Verify: ${widget.productName}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Check if the photo matches "${widget.productName}"',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _processing ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Camera'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _processing ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_library),
                label: const Text('Gallery'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_image != null) ...[
            const Text('INPUT:'),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(File(_image!.path), height: 200, fit: BoxFit.cover),
            ),
          ],
          const SizedBox(height: 12),
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
                          if (_matched != null) _check();
                        },
                ),
              ),
              Text('${_tolerance.toStringAsFixed(0)}%'),
            ],
          ),
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
                          if (_matched != null) _check();
                        },
                ),
              ),
              Text(_orbWeight.toStringAsFixed(1)),
            ],
          ),
          if (_processing) ...[
            const SizedBox(height: 12),
            const Center(
                child: SizedBox(
                    height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 3))),
          ],
          SwitchListTile(
            title: const Text('Show grid'),
            value: _showGrid,
            onChanged: (v) async {
              setState(() => _showGrid = v);
              if (_image != null && _matched != null) await _check();
            },
          ),
          if (_matched != null && !_processing) ...[
            const SizedBox(height: 8),
            if (_matched == true) ...[
              const Text('Match — bounding box with name shown above',
                  style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600)),
              if (_annotated != null) ...[
                const SizedBox(height: 12),
                const Text('OUTPUT:'),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_annotated!, height: 260, fit: BoxFit.cover),
                ),
              ],
              const SizedBox(height: 12),
              Text('Shape matrix (64×64)', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: _objects.map((o) {
                  final gridBytes = o.matrix != null
                      ? OpenCVService.matrixToGridImage(o.matrix!, label: o.label ?? 'no match')
                      : null;
                  return gridBytes == null
                      ? const SizedBox()
                      : Image.memory(gridBytes, width: 140, height: 150, fit: BoxFit.contain);
                }).toList(),
              ),
              const SizedBox(height: 8),
              ..._objects.where((o) => o.label != null).map(
                    (o) => Text(
                      '${o.label}: ${o.width}x${o.height}px  •  '
                      'ORB keypoints: ${o.orbDescriptorCount}'
                      '${o.matchDistance != null ? '  •  score: ${(o.matchDistance! * 100).toStringAsFixed(0)}%' : ''}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
            ] else
              const Text('No match for the selected product',
                  style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
          ],
        ],
      ),
    );
  }
}
