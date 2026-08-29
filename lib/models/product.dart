/// A single measured dimension pair (one training image).
class Measurement {
  final int width;
  final int height;
  final String sourceImage;

  /// Optional 64x64 binary matrix (1 = object body, 0 = background/hole).
  final List<int>? matrix;

  const Measurement({
    required this.width,
    required this.height,
    required this.sourceImage,
    this.matrix,
  });

  double get aspectRatio => height != 0 ? width / height : 0;

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'source_image': sourceImage,
        if (matrix != null) 'matrix': matrix,
      };

  static Measurement fromJson(Map<String, dynamic> json) => Measurement(
        width: (json['width'] as num).toInt(),
        height: (json['height'] as num).toInt(),
        sourceImage: json['source_image'] as String? ?? '',
        matrix: (json['matrix'] as List?)?.cast<int>(),
      );
}

/// A product with one or more reference measurements across images.
class Product {
  final String name;
  final List<Measurement> measurements;

  Product({required this.name, required this.measurements});

  /// Average reference width over all training images.
  int get width =>
      measurements.isEmpty ? 0 : (measurements.map((m) => m.width).reduce((a, b) => a + b) / measurements.length).round();

  /// Average reference height over all training images.
  int get height =>
      measurements.isEmpty ? 0 : (measurements.map((m) => m.height).reduce((a, b) => a + b) / measurements.length).round();

  double get aspectRatio => height != 0 ? width / height : 0;

  factory Product.fromJson(String name, Map<String, dynamic> json) {
    // New format: list of measurements
    final measureList = json['measurements'];
    if (measureList is List) {
      return Product(
        name: name,
        measurements: measureList
            .map((e) => Measurement.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
    }
    // Legacy single-measurement format
    final w = (json['width'] as num?)?.toInt() ?? 0;
    final h = (json['height'] as num?)?.toInt() ?? 0;
    final src = json['source_image'] as String? ?? '';
    return Product(
      name: name,
      measurements: [Measurement(width: w, height: h, sourceImage: src)],
    );
  }

  Map<String, dynamic> toJson() => {
        'measurements': measurements.map((m) => m.toJson()).toList(),
      };
}

class MatchResult {
  final String? matchedName;
  final double bestScore;
  final List<(String, double, double)> scores;
  final int inputWidth;
  final int inputHeight;
  final bool rotated;

  MatchResult({
    required this.matchedName,
    required this.bestScore,
    required this.scores,
    required this.inputWidth,
    required this.inputHeight,
    required this.rotated,
  });
}
