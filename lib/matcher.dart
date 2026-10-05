import 'models/product.dart';
import 'opencv_service.dart';

/// Matches detected objects against the trained product database.
///
/// Two-level approach:
///   1. dimension match (first pass, narrows the field and is a hard gate)
///   2. feature match (second pass, distinguishes same-size products)
///
/// The feature pass uses ORB ratio-test scores when both sides carry
/// descriptors, and falls back to the 64x64 matrix NCC for products trained
/// before ORB existed.
class ProductMatcher {
  /// Minimum feature similarity (0..1) a candidate must reach before it can be
  /// returned at all. Without this gate, anything that slipped past the
  /// dimension check used to be reported as a match, which is how a completely
  /// unrelated part could end up being "verified".
  static const double defaultMinFeatureScore = 0.30;

  /// Fallback floor applied when no features are comparable on either side
  /// (both the object and the product lack ORB descriptors *and* matrices).
  static const double defaultMinCombinedScore = 0.45;

  /// Compares one detected object against [products].
  ///
  /// [tolerancePct] is the max allowed % dimension difference.
  /// [featureWeight] (0..1) controls how much the ORB/matrix feature score
  /// matters relative to the dimensions.
  ///
  /// Returns the best candidate that clears the feature thresholds, or null
  /// when nothing is actually a match.
  static FeatureMatch? matchObject(
    List<Product> products,
    int inputWidth,
    int inputHeight,
    List<int>? inputOrbDescriptors,
    double tolerancePct,
    double featureWeight, {
    List<int>? inputMatrix,
    double minFeatureScore = defaultMinFeatureScore,
    double minCombinedScore = defaultMinCombinedScore,
  }) {
    if (products.isEmpty) return null;

    final candidates = <FeatureMatch>[];
    for (final p in products) {
      final dimensionScore =
          OpenCVService.distance(inputWidth, inputHeight, p.width, p.height);
      // Hard gate: dimensions must be close before features are considered.
      if (dimensionScore > tolerancePct) continue;

      final orb = inputOrbDescriptors;
      final matrix = inputMatrix;
      final inputHasOrb = orb != null && orb.isNotEmpty;
      final inputHasMatrix = matrix != null && matrix.isNotEmpty;

      // ORB is preferred; the matrix is the fallback for pre-ORB training data.
      final useOrb = inputHasOrb && p.hasOrbDescriptors;
      final useMatrix = !useOrb && inputHasMatrix && p.hasMatrix;

      // `orb`/`matrix` are non-null exactly when the matching useOrb/useMatrix
      // flag below is true, and Dart flow analysis promotes them accordingly.
      final featureScore = useOrb
          ? _bestOrbScore(p, orb)
          : useMatrix
              ? _bestMatrixScore(p, matrix)
              : 0.0;

      // Both sides are similarities in 0..1, so blend them directly.
      final dimSimilarity = (1.0 - dimensionScore / 100.0).clamp(0.0, 1.0);
      final combined =
          dimSimilarity * (1.0 - featureWeight) + featureScore * featureWeight;

      // Threshold gate: unrelated items that pass the dimension check are
      // reported as "no match" instead of being returned as the closest one.
      if (useOrb || useMatrix) {
        if (featureScore < minFeatureScore) continue;
      } else if (combined < minCombinedScore) {
        continue;
      }

      candidates.add(FeatureMatch(
        name: p.name,
        dimensionScore: dimensionScore,
        featureScore: featureScore,
        combinedScore: combined,
      ));
    }

    if (candidates.isEmpty) return null;
    candidates.sort((a, b) => b.combinedScore.compareTo(a.combinedScore));
    return candidates.first;
  }

  /// Best ORB similarity across every reference image of [product].
  static double _bestOrbScore(Product product, List<int> input) {
    var best = 0.0;
    for (final m in product.measurements) {
      final ref = m.orbDescriptors;
      if (ref == null || ref.isEmpty) continue;
      final score = OpenCVService.matchOrbDescriptors(ref, input);
      if (score > best) best = score;
    }
    return best;
  }

  /// Best 64x64 matrix similarity across every reference image of [product].
  /// The NCC value is a distance, so it is inverted to a similarity to keep the
  /// feature pass on one "higher is better" scale.
  static double _bestMatrixScore(Product product, List<int> input) {
    var best = 0.0;
    for (final m in product.measurements) {
      final ref = m.matrix;
      if (ref == null || ref.isEmpty) continue;
      final score = (1.0 - OpenCVService.nccDistance(input, ref)).clamp(0.0, 1.0);
      if (score > best) best = score;
    }
    return best;
  }
}
