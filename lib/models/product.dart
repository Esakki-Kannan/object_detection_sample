/// A single measured dimension pair (one training image).
class Measurement {
  /// Bytes per ORB descriptor. ORB uses a 256-bit BRIEF descriptor, so 32.
  static const int orbDescriptorBytes = 32;

  final int width;
  final int height;
  final String sourceImage;

  /// Optional 64x64 binary matrix (1 = object body, 0 = background/hole).
  /// Row-major, length = 64*64. Still used for the grid preview and as the
  /// fallback feature for products trained before ORB existed.
  final List<int>? matrix;

  /// Optional ORB/BRIEF descriptors for this image, flattened row-major into
  /// [orbDescriptorCount] x [orbDescriptorBytes] bytes. Stored as plain ints so
  /// no native OpenCV memory has to outlive the detection call.
  final List<int>? orbDescriptors;

  const Measurement({
    required this.width,
    required this.height,
    required this.sourceImage,
    this.matrix,
    this.orbDescriptors,
  });

  /// Number of ORB descriptors held by this measurement (0 when none).
  int get orbDescriptorCount =>
      orbDescriptors == null ? 0 : orbDescriptors!.length ~/ orbDescriptorBytes;

  bool get hasOrbDescriptors => orbDescriptorCount > 0;

  double get aspectRatio => height != 0 ? width / height : 0;

  Map<String, dynamic> toJson() => {
        'width': width,
        'height': height,
        'source_image': sourceImage,
        if (matrix != null) 'matrix': matrix,
        if (orbDescriptors != null) 'orb_descriptors': orbDescriptors,
        if (orbDescriptors != null) 'orb_descriptor_count': orbDescriptorCount,
      };

  static Measurement fromJson(Map<String, dynamic> json) => Measurement(
        width: (json['width'] as num).toInt(),
        height: (json['height'] as num).toInt(),
        sourceImage: json['source_image'] as String? ?? '',
        matrix: _intList(json['matrix']),
        orbDescriptors: _orbList(json['orb_descriptors']),
      );

  static List<int>? _intList(Object? raw) {
    if (raw is! List) return null;
    final list = raw.cast<num>().map((v) => v.toInt()).toList();
    return list.isEmpty ? null : list;
  }

  /// Accepts only complete, byte-aligned descriptor buffers so a corrupted
  /// products.json can never reach the matcher.
  static List<int>? _orbList(Object? raw) {
    final list = _intList(raw);
    if (list == null) return null;
    if (list.length % orbDescriptorBytes != 0) return null;
    return list.map((v) => v & 0xFF).toList(growable: false);
  }
}

/// A product with one or more reference measurements across images.
class Product {
  final String name;
  final List<Measurement> measurements;

  Product({required this.name, required this.measurements});

  /// Average reference width over all training images.
  ///
  /// Returns 1 instead of 0 when there is nothing to average: the value feeds
  /// straight into the dimension distance calculation as a divisor, and a 0
  /// there would produce Infinity/NaN scores.
  int get width => _average((m) => m.width);

  /// Average reference height over all training images. See [width].
  int get height => _average((m) => m.height);

  int _average(int Function(Measurement) pick) {
    if (measurements.isEmpty) return 1;
    var sum = 0;
    for (final m in measurements) {
      sum += pick(m);
    }
    final avg = (sum / measurements.length).round();
    return avg <= 0 ? 1 : avg;
  }

  double get aspectRatio => height != 0 ? width / height : 0;

  /// True when at least one training image produced ORB descriptors.
  bool get hasOrbDescriptors => measurements.any((m) => m.hasOrbDescriptors);

  /// True when at least one training image produced a 64x64 matrix.
  bool get hasMatrix => measurements.any((m) => m.matrix != null && m.matrix!.isNotEmpty);

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
    final w = (json['width'] as num?)?.toInt() ?? 1;
    final h = (json['height'] as num?)?.toInt() ?? 1;
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
