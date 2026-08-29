import 'package:flutter_test/flutter_test.dart';

import 'package:product_matcher/main.dart';

void main() {
  testWidgets('App builds without crashing', (WidgetTester tester) async {
    await tester.pumpWidget(const ProductMatcherApp());
    await tester.pump();
    expect(find.byType(ProductMatcherApp), findsOneWidget);
  });
}
