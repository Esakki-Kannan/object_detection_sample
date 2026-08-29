import 'package:flutter/material.dart';

import 'product_db.dart';
import 'screens/detect_screen.dart';
import 'screens/train_screen.dart';

void main() {
  runApp(const ProductMatcherApp());
}

class ProductMatcherApp extends StatelessWidget {
  const ProductMatcherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Product Matcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.green, useMaterial3: true),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final ProductDb _db = ProductDb();
  bool _ready = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _db.load();
    if (!mounted) return;
    setState(() => _ready = true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          DetectScreen(db: _db),
          TrainScreen(db: _db),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.search), label: 'Detect'),
          NavigationDestination(icon: Icon(Icons.add_box), label: 'Train'),
        ],
      ),
    );
  }
}
