// import 'package:flutter/material.dart';
// import 'package:product_matcher/screens/object_distance_2/services/distance_measure_screen.dart';
//
// import 'product_db.dart';
// import 'screens/detect_screen.dart';
// import 'screens/products_screen.dart';
// import 'screens/train_screen.dart';
//
// void main() {
//   runApp(const ProductMatcherApp());
// }
//
// class ProductMatcherApp extends StatelessWidget {
//   const ProductMatcherApp({super.key});
//
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Product Matcher',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
//       // home: const HomeShell(),
//
//       // home: DistanceCameraScreen(),
//       home: DistanceMeasureScreen(),
//
//     );
//   }
// }
//
// class HomeShell extends StatefulWidget {
//   const HomeShell({super.key});
//
//   @override
//   State<HomeShell> createState() => _HomeShellState();
// }
//
// class _HomeShellState extends State<HomeShell> {
//   final ProductDb _db = ProductDb();
//   bool _ready = false;
//   int _index = 0;
//
//   @override
//   void initState() {
//     super.initState();
//     _init();
//   }
//
//   Future<void> _init() async {
//     await _db.load();
//     if (!mounted) return;
//     setState(() => _ready = true);
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (!_ready) {
//       return const Scaffold(body: Center(child: CircularProgressIndicator()));
//     }
//     return Scaffold(
//       body: IndexedStack(
//         index: _index,
//         children: [
//           DetectScreen(db: _db),
//           TrainScreen(db: _db),
//           ProductsScreen(db: _db),
//         ],
//       ),
//       bottomNavigationBar: NavigationBar(
//         selectedIndex: _index,
//         onDestinationSelected: (i) => setState(() => _index = i),
//         destinations: const [
//           NavigationDestination(icon: Icon(Icons.search), label: 'Detect'),
//           NavigationDestination(icon: Icon(Icons.add_box), label: 'Train'),
//           NavigationDestination(icon: Icon(Icons.inventory), label: 'Products'),
//         ]
//       )
//     );
//   }
// }
//
//


// pubspec.yaml:
//   dependencies:
//     camera: ^0.11.0
//
// Android: minSdkVersion 21+. iOS: add NSCameraUsageDescription to Info.plist.
//
// Idea (pinhole model):  distance = realSize * focal / sizeInImage
// Focal length is calibrated once with a known distance.
// Keep the phone in portrait and the same zoom level for calibrate + measure.

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

late List<CameraDescription> cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MaterialApp(home: DistancePage()));
}

class DistancePage extends StatefulWidget {
  const DistancePage({super.key});
  @override
  State<DistancePage> createState() => _DistancePageState();
}

class _DistancePageState extends State<DistancePage> {
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
    final back = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.back,
      orElse: () => cameras.first,
    );
    _controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
    _controller!.initialize().then((_) {
      if (mounted) setState(() {});
    });
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
    if (rw == null || rh == null || rw <= 0 || rh <= 0 || _previewSize.width == 0) {
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
    setState(() => _focal = ppu * d); // f = (size_img / size_real) * distance
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
                        final dx = moved.left.clamp(0.0, _previewSize.width - moved.width);
                        final dy = moved.top.clamp(0.0, _previewSize.height - moved.height);
                        _box = Rect.fromLTWH(dx, dy, moved.width, moved.height);
                        _updateDistance();
                      }),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.greenAccent, width: 2),
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

// ---------------------------------------------------------------------------
// Alternative if you know the camera specs (no calibration needed):
//
// double focalPx = focalLengthMm * imageWidthPx / sensorWidthMm;
// double distance = realWidth * focalPx / objectWidthPx;
//
// To avoid manually drawing the box, get objectWidthPx automatically from an
// object detector such as google_mlkit_object_detection (bounding box width),
// feeding it frames from controller.startImageStream().
// ---------------------------------------------------------------------------