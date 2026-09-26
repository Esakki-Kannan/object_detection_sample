import 'models/product.dart';
import 'opencv_service.dart';

/// Compares a detected object (dimensions + optional matrix) against the
/// trained product database, using a two-level approach:
///   1. dimension match (first pass, narrows the field)
///   2. matrix NCC (second pass, distinguishes same-size products)
class ProductMatcher {
  /// [tolerancePct] is the max allowed average % dimension difference.
  /// [matrixWeight] (0..1) controls how much the internal matrix matters.
  /// Returns null if no product matches dimensions AND matrix within limits.
  static MatrixMatch? matchObject(
    List<Product> products,
    int inputWidth,
    int inputHeight,
    List<int>? inputMatrix,
    double tolerancePct,
    double matrixWeight,
  ) {
    print('tolerancepct $tolerancePct, ,matrixweight $matrixWeight');
    final candidates = <MatrixMatch>[];
    for (final p in products) {
      final dimensionScore = OpenCVService.distance(inputWidth, inputHeight, p.width, p.height);
      // Skip products that clearly fail the dimension pass
      if (dimensionScore > tolerancePct) continue;

      // Matrix score: how well the detected matrix matches this product's
      // trained matrix (average across all its measurement matrices).
      double matrixScore = 1.0;
      if (inputMatrix != null && inputMatrix.isNotEmpty) {
        final refMatrices = p.measurements
            .map((m) => m.matrix)
            .whereType<List<int>>()
            .toList();
        if (refMatrices.isNotEmpty) {
          double best = 1.0;
          for (final ref in refMatrices) {
            final d = OpenCVService.nccDistance(inputMatrix, ref);
            if (d < best) best = d;
          }
          matrixScore = best;
        } else {
          // Product trained without a matrix: rely on dimensions only.
          matrixScore = 0.0;
        }
      } else {
        // No detected matrix available: rely on dimensions only.
        matrixScore = 0.0;
      }

      // Combined score (dimension in % scaled to 0..1, added to NCC distance)
      final normalizedDim = (dimensionScore / 100).clamp(0.0, 1.0);
      final combined = normalizedDim * (1.0 - matrixWeight) + matrixScore * matrixWeight;

      candidates.add(MatrixMatch(
        name: p.name,
        dimensionScore: dimensionScore,
        matrixScore: matrixScore,
        combinedScore: combined,
      ));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => a.combinedScore.compareTo(b.combinedScore));
    return candidates.first;
  }

  /// Backward-compatible dimension-only match (used where no matrix exists).
  static MatchResult match(
    List<Product> products,
    int inputWidth,
    int inputHeight,
    double tolerancePct,
  ) {
    final scores = <(String, double, double)>[];
    String? matched;
    double bestScore = double.infinity;
    bool rotated = false;

    for (final p in products) {
      final dNormal = _maxPct(inputWidth, inputHeight, p.width, p.height);
      final dRotated = _maxPct(inputWidth, inputHeight, p.height, p.width);
      final best = dNormal < dRotated ? dNormal : dRotated;
      final isRotated = dRotated < dNormal;

      scores.add((p.name, best, isRotated ? dRotated : dNormal));
      if (best < bestScore) {
        bestScore = best;
        matched = p.name;
        rotated = isRotated;
      }
    }

    scores.sort((a, b) => a.$2.compareTo(b.$2));

    return MatchResult(
      matchedName: bestScore <= tolerancePct ? matched : null,
      bestScore: bestScore,
      scores: scores,
      inputWidth: inputWidth,
      inputHeight: inputHeight,
      rotated: rotated,
    );
  }

  static double _maxPct(int w1, int h1, int w2, int h2) {
    final wp = ((w1 - w2).abs() / w2) * 100;
    final hp = ((h1 - h2).abs() / h2) * 100;
    return wp > hp ? wp : hp;
  }

  static double distance(int w1, int h1, int w2, int h2) =>
      OpenCVService.distance(w1, h1, w2, h2);
}
