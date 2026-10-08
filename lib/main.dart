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

import 'package:flutter/material.dart';
import 'package:product_matcher/screens/object_distance_2/calibrate_and_measure_distance/calibrate_and_measure.dart';


void main() {
  runApp(const MyApp());
}
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(title: const Text('Home')),
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => CalibrateAndMeasurePage(),
                ),
              );
            },
            child: const Text('Open distance measurement'),
          ),
        ),
      ),
    );
  }
}