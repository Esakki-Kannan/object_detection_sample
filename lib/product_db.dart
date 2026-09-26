import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'models/product.dart';

/// Loads/saves the product database to a JSON file in app documents dir.
class ProductDb {
  static const _fileName = 'products.json';
  static const _verifiedFile = 'verified.json';
  Map<String, Product> _products = {};
  Set<String> _verified = {};

  Map<String, Product> get products => _products;
  Set<String> get verified => _verified;
  bool isVerified(String name) => _verified.contains(name);

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  Future<File> _verifiedFileRef() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_verifiedFile');
  }

  Future<void> load() async {
    final f = await _file();
    if (!await f.exists()) {
      _products = {};
    } else {
      final text = await f.readAsString();
      final data = jsonDecode(text) as Map<String, dynamic>;
      _products = data.map((k, v) => MapEntry(k, Product.fromJson(k, v as Map<String, dynamic>)));
    }
    final vf = await _verifiedFileRef();
    if (await vf.exists()) {
      try {
        final list = jsonDecode(await vf.readAsString()) as List;
        _verified = list.cast<String>().toSet();
      } catch (_) {
        _verified = {};
      }
    } else {
      _verified = {};
    }
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
    _verified.remove(name);
    await save();
    await _saveVerified();
  }

  Future<void> markVerified(String name) async {
    _verified.add(name);
    await _saveVerified();
  }

  Future<void> clearVerified() async {
    _verified.clear();
    await _saveVerified();
  }

  Future<void> _saveVerified() async {
    final vf = await _verifiedFileRef();
    await vf.writeAsString(jsonEncode(_verified.toList()));
  }
}
