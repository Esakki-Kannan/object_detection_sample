import 'package:flutter/material.dart';

import '../product_db.dart';
import 'product_verify_screen.dart';

class ProductsScreen extends StatefulWidget {
  final ProductDb db;
  const ProductsScreen({super.key, required this.db});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  @override
  Widget build(BuildContext context) {
    final products = widget.db.products.values.toList()..sort((a, b) => a.name.compareTo(b.name));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          TextButton.icon(
            onPressed: widget.db.verified.isEmpty
                ? null
                : () async {
                    await widget.db.clearVerified();
                    if (!mounted) return;
                    setState(() {});
                    // ignore: use_build_context_synchronously
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Cleared verified status')),
                    );
                  },
            icon: const Icon(Icons.clear_all, size: 18),
            label: const Text('Clear'),
          ),
        ],
      ),
      body: products.isEmpty
          ? const Center(child: Text('No trained products yet.\nGo to Train to add some.', textAlign: TextAlign.center))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: products.length,
              itemBuilder: (context, i) {
                final p = products[i];
                final verified = widget.db.isVerified(p.name);
                return Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: verified ? Colors.green : Colors.grey, width: verified ? 2 : 1.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    leading: Icon(Icons.inventory_2, color: verified ? Colors.green : Colors.grey),
                    title: Text(p.name, style: TextStyle(fontWeight: FontWeight.w600, color: verified ? Colors.green.shade800 : null)),
                    subtitle: Text(verified ? 'Verified' : ''),
                    trailing: verified
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : const Icon(Icons.chevron_right),
                    onTap: () async {
                      final result = await Navigator.of(context).push<bool>(
                        MaterialPageRoute(builder: (_) => ProductVerifyScreen(db: widget.db, productName: p.name)),
                      );
                      if (result == true && mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
    );
  }
}
