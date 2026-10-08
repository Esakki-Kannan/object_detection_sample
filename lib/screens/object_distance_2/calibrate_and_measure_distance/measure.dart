/ calibrate_and_measure.dart  (no calibration version)
// 1) Capture image  2) Enter length & width  3) Tap "Calculate distance"
//
// Focal length comes from the camera hardware (platform channel "camera_info"),
// with a fallback to a 35mm-equivalent estimate if the hardware lookup fails.

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class Measure extends StatefulWidget {
  const Measure({super.key});

  @override
  State<Measure> createState() =>
      _MeasureState();
}

class _MeasureState extends State<Measure> {
  CameraController? _controller;

  XFile? _photo; // captured image (null = live preview mode)
  bool _capturing = false;

  // Box the user fits around the object on the captured photo
  Rect _box = const Rect.fromLTWH(80, 160, 160, 160);
  Size _previewSize = Size.zero;

  final _length = TextEditingController(); // real length of the part
  final _width = TextEditingController(); // real width of the part

  double? _focal; // focal length in "image-width" units
  double? _distance;
  String? _error;

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

    final aspect = _controller!.value.aspectRatio; // landscape long/short
    _focal = await _focalFromHardware(back, aspect) ??
        _focalFrom35mm(26, aspect); // fallback estimate
    debugPrint('focal (image-width units): $_focal');

    if (mounted) setState(() {});
  }

  // Width of the image (portrait) in mm, given sensor size and output aspect.
  // If the output is wider than the sensor (e.g. 16:9 from a 4:3 sensor),
  // the short side is cropped.
  double _effectiveShortSide(double sw, double sh, double aspect) {
    final sensorLong = sw > sh ? sw : sh;
    final sensorShort = sw > sh ? sh : sw;
    final sensorAspect = sensorLong / sensorShort;
    return aspect > sensorAspect ? sensorLong / aspect : sensorShort;
  }

  Future<double?> _focalFromHardware(CameraDescription cam, double aspect) async {
    const channel = MethodChannel('camera_info');
    try {
      final r = await channel.invokeMethod<Map>('getCameraInfo', {
        'front': cam.lensDirection == CameraLensDirection.front,
      });
      debugPrint('native result: $r');
      if (r == null) return null;

      final focalMm = (r['focalMm'] as num).toDouble();
      final sw = (r['sensorW'] as num).toDouble();
      final sh = (r['sensorH'] as num).toDouble();
      return focalMm / _effectiveShortSide(sw, sh, aspect);
    } on PlatformException catch (e) {
      debugPrint('Native error: ${e.code} ${e.message}');
    } catch (e) {
      debugPrint('Other error: $e');
    }
    return null;
  }

  // Fallback using the 35mm-equivalent focal length (diagonal 43.27mm).
  double _focalFrom35mm(double f35, double aspect) {
    const longSide35 = 34.6; // 4:3 frame, 35mm-equivalent
    const shortSide35 = 25.95;
    final eff = aspect > 4 / 3 ? longSide35 / aspect : shortSide35;
    return f35 / eff;
  }

  @override
  void dispose() {
    _controller?.dispose();
    _length.dispose();
    _width.dispose();
    super.dispose();
  }

  // ---------------- actions ----------------

  Future<void> _takePhoto() async {
    final c = _controller;
    if (c == null || !c.value.isInitialized || _capturing) return;
    setState(() => _capturing = true);
    try {
      final file = await c.takePicture();
      if (!mounted) return;
      setState(() {
        _photo = file;
        _capturing = false;
        _distance = null;
        _error = null;
      });
    } catch (e) {
      debugPrint('Capture error: $e');
      if (mounted) setState(() => _capturing = false);
    }
  }

  void _retake() {
    setState(() {
      _photo = null;
      _distance = null;
      _error = null;
    });
  }

  void _calculate() {
    final len = double.tryParse(_length.text);
    final wid = double.tryParse(_width.text);

    if (len == null || wid == null || len <= 0 || wid <= 0) {
      setState(() {
        _distance = null;
        _error = 'Enter a valid length and width';
      });
      return;
    }
    if (_focal == null || _previewSize.width == 0) {
      setState(() {
        _distance = null;
        _error = 'Camera info not ready';
      });
      return;
    }

    // box size as a fraction of the image width
    final boxW = _box.width / _previewSize.width;
    final boxH = _box.height / _previewSize.width;

    // distance = real * focal / size_in_image  (averaged over both sides)
    final dFromWidth = wid * _focal! / boxW;
    final dFromLength = len * _focal! / boxH;

    setState(() {
      _distance = (dFromWidth + dFromLength) / 2;
      _error = null;
    });
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final hasPhoto = _photo != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Object distance')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 1 / c.value.aspectRatio,
            child: LayoutBuilder(builder: (context, cons) {
              _previewSize = Size(cons.maxWidth, cons.maxHeight);

              if (!hasPhoto) return CameraPreview(c); // live camera

              return Stack(
                children: [
                  Positioned.fill(
                    child: Image.file(File(_photo!.path), fit: BoxFit.cover),
                  ),
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
                        _distance = null; // result is stale after moving
                      }),
                      child: Container(
                        decoration: BoxDecoration(
                          border:
                          Border.all(color: Colors.greenAccent, width: 2),
                        ),
                      ),
                    ),
                  ),
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
                        _distance = null;
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
              child: hasPhoto ? _measurePanel() : _cameraPanel(),
            ),
          ),
        ],
      ),
    );
  }

  // Step 1: capture
  Widget _cameraPanel() {
    return Column(
      children: [
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _capturing ? null : _takePhoto,
          icon: const Icon(Icons.camera_alt),
          label: Text(_capturing ? 'Capturing...' : 'Camera'),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          ),
        ),
        const SizedBox(height: 8),
        const Text('Take a photo of the part.'),
      ],
    );
  }

  // Steps 2 & 3: enter size, calculate
  Widget _measurePanel() {
    return Column(
      children: [
        Row(children: [
          _field(_length, 'Part length'),
          const SizedBox(width: 8),
          _field(_width, 'Part width'),
        ]),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton(
              onPressed: _calculate,
              child: const Text('Calculate distance'),
            ),
            const SizedBox(width: 12),
            OutlinedButton.icon(
              onPressed: _retake,
              icon: const Icon(Icons.refresh),
              label: const Text('Retake'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_error != null)
          Text(_error!, style: const TextStyle(color: Colors.red))
        else if (_distance != null)
          Text(
            'Distance ≈ ${_distance!.toStringAsFixed(1)}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label) => Expanded(
    child: TextField(
      controller: c,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label, isDense: true),
    ),
  );
}