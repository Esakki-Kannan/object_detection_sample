import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models/product.dart';

/// Loads/saves the product database to a JSON file in app documents dir.
class ProductDb {
  static const _fileName = 'products.json';
  Map<String, Product> _products = {};

  Map<String, Product> get products => _products;

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<void> load() async {
    final f = await _file();
    if (!await f.exists()) {
      _products = {};
      return;
    }
    final text = await f.readAsString();
    final data = jsonDecode(text) as Map<String, dynamic>;
    _products = data.map((k, v) => MapEntry(k, Product.fromJson(k, v as Map<String, dynamic>)));
  }

  Future<void> save() async {
    final f = await _file();
    final data = _products.map((k, v) => MapEntry(k, v.toJson()));
    await f.writeAsString(jsonEncode(data));
  }

  Future<void> addOrUpdate(Product p) async {
    _products[p.name] = p;
    await save();
  }

  /// Adds a single measured image to an existing product (creating it if new).
  Future<void> addMeasurement(String name, Measurement m) async {
    final existing = _products[name];
    final list = existing != null ? [...existing.measurements, m] : [m];
    _products[name] = Product(name: name, measurements: list);
    await save();
  }

  Future<void> remove(String name) async {
    _products.remove(name);
    await save();
  }
}
