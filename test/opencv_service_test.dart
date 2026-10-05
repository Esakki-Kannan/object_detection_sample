import 'package:flutter_test/flutter_test.dart';
import 'package:product_matcher/matcher.dart';
import 'package:product_matcher/models/product.dart';
import 'package:product_matcher/opencv_service.dart';

/// Deterministic pseudo-random byte generator so descriptor fixtures are
/// stable across runs and platforms.
List<int> _orbDescriptors(int count, {int seed = 1}) {
  final out = List<int>.filled(count * OpenCVService.orbDescriptorBytes, 0);
  var state = seed;
  for (var i = 0; i < out.length; i++) {
    state = (1103515245 * state + 12345) & 0x7fffffff;
    out[i] = (state >> 8) & 0xFF;
  }
  return out;
}

/// A 64x64 binary "shape" with real variance. A constant matrix (all 0s/all
/// 1s) has zero variance, so NCC correlation is undefined for it and cannot be
/// used as a match fixture.
List<int> _shape({bool inverted = false}) {
  final out = List<int>.filled(64 * 64, 0);
  for (var r = 0; r < 64; r++) {
    for (var c = 0; c < 64; c++) {
      final on = (r < 20 && c < 40) || (r >= 30 && r < 50 && c >= 10 && c < 55);
      out[r * 64 + c] = (inverted ? !on : on) ? 1 : 0;
    }
  }
  return out;
}

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

  group('OpenCVService.matchOrbDescriptors', () {
    test('identical descriptors -> similarity 1', () {
      final ref = _orbDescriptors(24, seed: 7);
      final score = OpenCVService.matchOrbDescriptors(ref, List<int>.from(ref));
      expect(score, greaterThan(0.9));
    });

    test('unrelated descriptors -> low similarity', () {
      final ref = _orbDescriptors(24, seed: 7);
      final test = _orbDescriptors(24, seed: 991);
      expect(OpenCVService.matchOrbDescriptors(ref, test), lessThan(0.5));
    });

    test('missing inputs -> 0', () {
      expect(OpenCVService.matchOrbDescriptors(null, null), 0.0);
      expect(OpenCVService.matchOrbDescriptors(const [], const []), 0.0);
      expect(OpenCVService.matchOrbDescriptors(const [1], null), 0.0);
    });

    test('single test descriptor falls back to an absolute Hamming ceiling', () {
      final ref = _orbDescriptors(8, seed: 3);
      final one = ref.sublist(0, OpenCVService.orbDescriptorBytes);
      expect(OpenCVService.matchOrbDescriptors(ref, one), greaterThan(0.0));
    });
  });

  group('OpenCVService.distance', () {
    test('zero reference dimensions do not divide by zero', () {
      expect(OpenCVService.distance(10, 20, 0, 0).isFinite, isTrue);
      expect(OpenCVService.distance(10, 20, 0, 0).isNaN, isFalse);
    });
  });

  group('Measurement JSON (matrix + ORB storage)', () {
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

    test('orb descriptors round-trip through JSON', () {
      final orbs = _orbDescriptors(4, seed: 11);
      final m = Measurement(
        width: 60,
        height: 40,
        sourceImage: 'b.jpg',
        orbDescriptors: orbs,
      );
      final json = m.toJson();
      expect(json['orb_descriptor_count'], 4);

      final restored = Measurement.fromJson({
        'width': json['width'],
        'height': json['height'],
        'source_image': json['source_image'],
        'orb_descriptors': json['orb_descriptors'],
        'orb_descriptor_count': json['orb_descriptor_count'],
      });
      expect(restored.orbDescriptors, orbs);
      expect(restored.orbDescriptorCount, 4);
      expect(restored.hasOrbDescriptors, isTrue);
    });

    test('orb descriptor buffer that is not byte-aligned is discarded', () {
      final restored = Measurement.fromJson({
        'width': 60,
        'height': 40,
        'source_image': 'b.jpg',
        'orb_descriptors': [1, 2, 3, 4, 5],
      });
      expect(restored.orbDescriptors, isNull);
      expect(restored.orbDescriptorCount, 0);
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

    test('empty measurements never produce a zero dimension', () {
      final p = Product(name: 'empty', measurements: const []);
      expect(p.width, greaterThan(0));
      expect(p.height, greaterThan(0));
      expect(p.aspectRatio.isFinite, isTrue);
    });
  });

  group('ProductMatcher.matchObject', () {
    Measurement matrixMeasure(List<int> matrix) => Measurement(
          width: 100,
          height: 100,
          sourceImage: 'ref.jpg',
          matrix: matrix,
        );

    test('unrelated shape that passes the dimension gate is rejected', () {
      final product = Product(name: 'battery', measurements: [matrixMeasure(_shape())]);
      // Same dimensions as the reference, so it clears the hard gate, but the
      // shape is completely different -> must NOT be reported as a match.
      final match = ProductMatcher.matchObject(
        [product],
        100,
        100,
        null,
        10,
        0.6,
        inputMatrix: _shape(inverted: true),
      );
      expect(match, isNull);
    });

    test('identical shape at identical size is matched', () {
      final product = Product(name: 'battery', measurements: [matrixMeasure(_shape())]);
      final match = ProductMatcher.matchObject(
        [product],
        100,
        100,
        null,
        10,
        0.6,
        inputMatrix: _shape(),
      );
      expect(match, isNotNull);
      expect(match!.name, 'battery');
      expect(match.featureScore, greaterThan(0.9));
      expect(match.dimensionScore, closeTo(0.0, 1e-6));
    });

    test('size outside tolerance is rejected even with matching shape', () {
      final product = Product(name: 'battery', measurements: [matrixMeasure(_shape())]);
      final match = ProductMatcher.matchObject(
        [product],
        200,
        100,
        null,
        10,
        0.6,
        inputMatrix: _shape(),
      );
      expect(match, isNull);
    });

    test('ORB descriptors decide the match when both sides have them', () {
      final ref = _orbDescriptors(20, seed: 42);
      final product = Product(
        name: 'bracket',
        measurements: [
          Measurement(
            width: 100,
            height: 100,
            sourceImage: 'ref.jpg',
            orbDescriptors: ref,
          ),
        ],
      );

      final hit = ProductMatcher.matchObject(
        [product],
        100,
        100,
        List<int>.from(ref),
        10,
        0.6,
      );
      expect(hit, isNotNull);
      expect(hit!.featureScore, greaterThan(0.8));

      final miss = ProductMatcher.matchObject(
        [product],
        100,
        100,
        _orbDescriptors(20, seed: 4242),
        10,
        0.6,
      );
      expect(miss, isNull);
    });

    test('no products -> null', () {
      expect(ProductMatcher.matchObject(const [], 10, 10, null, 10, 0.6), isNull);
    });
  });
}
