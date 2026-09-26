import 'package:flutter_test/flutter_test.dart';
import 'package:product_matcher/models/product.dart';
import 'package:product_matcher/opencv_service.dart';

void main() {
  group('OpenCVService.nccDistance', () {
    test('identical matrices -> distance 0', () {
      final a = List<int>.generate(64 * 64, (i) => i < 32 * 64 ? 1 : 0);
      final b = List<int>.from(a);
      expect(OpenCVService.nccDistance(a, b), closeTo(0.0, 1e-6));
    });

    test('completely different (inverted) -> higher distance', () {
      final a = List<int>.generate(64 * 64, (i) => 1);
      final b = List<int>.generate(64 * 64, (i) => 0);
      expect(OpenCVService.nccDistance(a, b), greaterThan(0.5));
    });

    test('small shift tolerated (low distance)', () {
      final a = List<int>.generate(64 * 64, (i) => 0);
      final b = List<int>.generate(64 * 64, (i) => 0);
      // Put a small filled region, shifted by 1 cell
      for (var r = 5; r < 10; r++) {
        for (var c = 5; c < 10; c++) {
          a[r * 64 + c] = 1;
          b[(r + 1) * 64 + (c + 1)] = 1;
        }
      }
      final d = OpenCVService.nccDistance(a, b);
      expect(d, lessThan(0.5));
    });
  });

  group('Measurement JSON (matrix storage)', () {
    test('matrix round-trips through JSON', () {
      final matrix = List<int>.generate(64 * 64, (i) => i % 2);
      final m = Measurement(
        width: 100,
        height: 200,
        sourceImage: 'a.jpg',
        matrix: matrix,
      );
      final json = m.toJson()['matrix'];
      final restored = Measurement.fromJson({
        'width': 100,
        'height': 200,
        'source_image': 'a.jpg',
        'matrix': json,
      });
      expect(restored.matrix, matrix);
      expect(restored.width, 100);
      expect(restored.height, 200);
    });
  });

  group('Product legacy & multi measurement', () {
    test('parses legacy single-measurement JSON', () {
      final p = Product.fromJson('batt', {
        'width': 50,
        'height': 80,
        'source_image': 'x.jpg',
      });
      expect(p.measurements.length, 1);
      expect(p.width, 50);
      expect(p.height, 80);
    });

    test('averages multiple measurements', () {
      final p = Product(name: 'batt', measurements: const [
        Measurement(width: 100, height: 200, sourceImage: 'a.jpg'),
        Measurement(width: 104, height: 198, sourceImage: 'b.jpg'),
      ]);
      expect(p.width, 102);
      expect(p.height, 199);
    });
  });
}
