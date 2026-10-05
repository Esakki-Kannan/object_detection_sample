import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:product_matcher/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // `ProductDb.load()` resolves the documents directory through
  // path_provider, which is not registered in a plain unit-test host.
  const pathChannel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() {
    final root = Directory.systemTemp.createTempSync('product_matcher_test').path;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') return root;
      throw MissingPluginException('Not implemented: ${call.method}');
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(pathChannel, null);
  });

  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const ProductMatcherApp());
      // HomeShell shows a spinner until the async ProductDb.load() finishes.
      // That load does real dart:io work, so it only completes inside
      // runAsync; pump a bounded number of frames to let it settle.
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 25));
        await tester.pump();
        if (find.text('Detect Products').evaluate().isNotEmpty) break;
      }
    });

    expect(find.byType(ProductMatcherApp), findsOneWidget);
    expect(find.text('Detect Products'), findsOneWidget);
  });
}
