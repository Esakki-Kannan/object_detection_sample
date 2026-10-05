import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/product.dart';
import '../opencv_service.dart';
import '../product_db.dart';

class TrainScreen extends StatefulWidget {
  final ProductDb db;
  const TrainScreen({super.key, required this.db});

  @override
  State<TrainScreen> createState() => _TrainScreenState();
}

class _TrainScreenState extends State<TrainScreen> {
  final _nameController = TextEditingController();
  String _currentName = '';
  XFile? _image;
  ({int width, int height})? _dims;
  DetectedObject? _obj;
  String? _status;
  bool _processing = false;
  final List<XFile> _pendingImages = [];

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final file = await picker.pickImage(source: source, maxWidth: 2048, maxHeight: 2048);
    if (file == null) return;
    setState(() {
      if (_currentName.isEmpty) {
        _currentName = _nameController.text.trim();
      }
      _pendingImages.add(file);
      _image = file;
      _dims = null;
      _status = null;
    });
    _measure();
  }

  Future<void> _measure() async {
    if (_pendingImages.isEmpty) return;
    final file = _pendingImages.last;
    setState(() {
      _processing = true;
      _status = 'Measuring...';
    });
    final bytes = await file.readAsBytes();
    final objects = OpenCVService.detectGreenObjectsBytes(bytes);
    DetectedObject? largest;
    for (final o in objects) {
      if (largest == null || o.area > largest.area) largest = o;
    }
    final dims = largest == null ? null : (width: largest.width, height: largest.height);
    setState(() {
      _dims = dims;
      _obj = largest;
      _status = dims == null
          ? 'No green object detected'
          : 'Detected: ${dims.width} x ${dims.height} px'
              '${largest!.hasOrbDescriptors ? ' (ORB: ${largest.orbDescriptorCount} keypoints)' : ' (no ORB features)'}'
              '${largest.matrix != null ? '  + 64x64 matrix' : ''}';
      _processing = false;
    });
  }

  Future<void> _saveMeasurement() async {
    var name = _currentName.trim();
    if (name.isEmpty) name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a product name first')),
      );
      return;
    }
    if (_dims == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No measurement to save')),
      );
      return;
    }
    final file = _pendingImages.last;
    final m = Measurement(
      width: _dims!.width,
      height: _dims!.height,
      sourceImage: file.name,
      matrix: _obj?.matrix,
      orbDescriptors: _obj?.orbDescriptors,
    );
    await widget.db.addMeasurement(name, m);
    if (!mounted) return;
    final orbCount = m.orbDescriptorCount;
    setState(() {
      _pendingImages.clear();
      _image = null;
      _dims = null;
      _obj = null;
      _currentName = name;
      _status = 'Added measurement to "$name"'
          '${orbCount > 0 ? ' (ORB: $orbCount descriptors)' : ''}';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Measurement saved to "$name"')),
    );
  }

  Future<void> _finishNewProduct() async {
    setState(() {
      _currentName = '';
      _nameController.clear();
      _status = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ready to train a new product')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = widget.db.products;
    return Scaffold(
      appBar: AppBar(title: const Text('Train Products')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Product name',
              style: Theme.of(context).textTheme.titleMedium),
          TextField(
            controller: _nameController,
            enabled: _currentName.isEmpty,
            decoration: InputDecoration(
              hintText: 'e.g. battery, screw, bracket',
              border: const OutlineInputBorder(),
              suffixIcon: _currentName.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.check),
                      onPressed: () {},
                      tooltip: 'Current product',
                    )
                  : null,
            ),
          ),
          if (_currentName.isNotEmpty) ...[
            const SizedBox(height: 8),
            Chip(
              avatar: const Icon(Icons.category, size: 18),
              label: Text('Adding images to: $_currentName'),
              deleteIcon: const Icon(Icons.close, size: 18),
              onDeleted: _finishNewProduct,
            ),
          ],
          const SizedBox(height: 16),
          Text('Pick an image', style: Theme.of(context).textTheme.titleMedium),
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
          const SizedBox(height: 12),
          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(_image!.path),
                height: 220,
                fit: BoxFit.cover,
              ),
            ),
          if (_status != null) ...[
            const SizedBox(height: 8),
            Text(_status!, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
          if (_processing) ...[
            const SizedBox(height: 12),
            const Center(
                child: SizedBox(
                    height: 24, width: 24,
                    child: CircularProgressIndicator(strokeWidth: 3))),
          ],
          if (_dims != null) ...[
            const SizedBox(height: 16),
            Text('Measurements for "$_currentName": ${_pendingImages.length}',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _saveMeasurement,
              icon: const Icon(Icons.add),
              label: Text(_pendingImages.length > 1
                  ? 'Save & Continue (same product)'
                  : 'Save this measurement'),
            ),
            const SizedBox(height: 12),
            if (widget.db.products.containsKey(_currentName))
              Text(
                'Replaces stored reference: ${widget.db.products[_currentName]!.measurements.length} image(s) '
                '-> ${widget.db.products[_currentName]!.measurements.length + _pendingImages.length}',
                style: const TextStyle(color: Colors.grey),
              ),
          ],
          const Divider(height: 40),
          Text('Saved Products (${products.length})',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (products.isEmpty)
            const Text('No products trained yet.')
          else
            ...products.values.map((p) => ListTile(
                  leading: const Icon(Icons.category),
                  title: Text(p.name),
                  subtitle: Text(
                      'avg ${p.width} x ${p.height} px  •  ${p.measurements.length} image(s)'
                      '  •  ${p.hasOrbDescriptors ? 'ORB ready' : 'no ORB'}'),
                  onTap: () {
                    setState(() {
                      _currentName = p.name;
                      _nameController.text = p.name;
                    });
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Adding to "${p.name}"')),
                    );
                  },
                  trailing: IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),
                    onPressed: () async {
                      await widget.db.remove(p.name);
                      setState(() {});
                    },
                  ),
                )),
        ],
      ),
    );
  }
}
