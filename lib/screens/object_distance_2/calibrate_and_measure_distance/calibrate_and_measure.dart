// calibrate_and_measure.dart
// Reusable page: calibrate once, then measure distance for any object
// by entering its real width and height.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class CalibrateAndMeasurePage extends StatefulWidget {

  const CalibrateAndMeasurePage({super.key});

  @override
  State<CalibrateAndMeasurePage> createState() =>
      _CalibrateAndMeasurePageState();
}

class _CalibrateAndMeasurePageState extends State<CalibrateAndMeasurePage> {
  CameraController? _controller;

  // Bounding box drawn over the object (in preview widget coordinates)
  Rect _box = const Rect.fromLTWH(80, 160, 160, 160);
  Size _previewSize = Size.zero;

  final _realW = TextEditingController(text: '8.5'); // e.g. cm
  final _realH = TextEditingController(text: '5.4'); // same unit as above
  final _knownDist = TextEditingController(text: '30'); // same unit

  double? _focal; // calibrated focal length (in "preview-width" units)
  double? _distance;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    final cameras = await availableCameras();
    final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _controller =
        CameraController(back, ResolutionPreset.high, enableAudio: false);
    await _controller!.initialize();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller?.dispose();
    _realW.dispose();
    _realH.dispose();
    _knownDist.dispose();
    super.dispose();
  }

  // Average "pixels per real-world unit" from box width and height.
  // Both measured relative to the preview width so one focal value works.
  double? _pixelsPerUnit() {
    final rw = double.tryParse(_realW.text);
    final rh = double.tryParse(_realH.text);
    if (rw == null ||
        rh == null ||
        rw <= 0 ||
        rh <= 0 ||
        _previewSize.width == 0) {
      return null;
    }
    final pw = _box.width / _previewSize.width;
    final ph = _box.height / _previewSize.width;
    return ((pw / rw) + (ph / rh)) / 2;
  }

  void _calibrate() {
    final ppu = _pixelsPerUnit();
    final d = double.tryParse(_knownDist.text);
    if (ppu == null || d == null || d <= 0) return;
    setState(() {
      _focal = ppu * d; // f = (size_img / size_real) * distance
      _updateDistance();
    });
  }

  void _updateDistance() {
    final ppu = _pixelsPerUnit();
    if (_focal == null || ppu == null) return;
    _distance = _focal! / ppu; // d = f * real / size_img
  }

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Object distance')),
      body: Column(
        children: [
          AspectRatio(
            // camera aspectRatio is landscape (w/h > 1); invert for portrait
            aspectRatio: 1 / c.value.aspectRatio,
            child: LayoutBuilder(builder: (context, cons) {
              _previewSize = Size(cons.maxWidth, cons.maxHeight);
              return Stack(
                children: [
                  Positioned.fill(child: CameraPreview(c)),
                  // movable box
                  Positioned.fromRect(
                    rect: _box,
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() {
                        final moved = _box.shift(d.delta);
                        final dx = moved.left
                            .clamp(0.0, _previewSize.width - moved.width);
                        final dy = moved.top
                            .clamp(0.0, _previewSize.height - moved.height);
                        _box = Rect.fromLTWH(dx, dy, moved.width, moved.height);
                        _updateDistance();
                      }),
                      child: Container(
                        decoration: BoxDecoration(
                          border:
                          Border.all(color: Colors.greenAccent, width: 2),
                        ),
                      ),
                    ),
                  ),
                  // resize handle (bottom-right corner)
                  Positioned(
                    left: _box.right - 16,
                    top: _box.bottom - 16,
                    child: GestureDetector(
                      onPanUpdate: (d) => setState(() {
                        final w = (_box.width + d.delta.dx)
                            .clamp(40.0, _previewSize.width - _box.left);
                        final h = (_box.height + d.delta.dy)
                            .clamp(40.0, _previewSize.height - _box.top);
                        _box = Rect.fromLTWH(_box.left, _box.top, w, h);
                        _updateDistance();
                      }),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Colors.greenAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(children: [
                    _field(_realW, 'Real width'),
                    const SizedBox(width: 8),
                    _field(_realH, 'Real height'),
                    const SizedBox(width: 8),
                    _field(_knownDist, 'Known dist.'),
                  ]),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: _calibrate,
                    child: const Text('Calibrate (object at known distance)'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _focal == null
                        ? 'Calibrate first'
                        : _distance == null
                        ? 'Move the box'
                        : 'Distance ≈ ${_distance!.toStringAsFixed(1)}',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(TextEditingController c, String label) => Expanded(
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: (_) => setState(_updateDistance),
    ),
  );
}