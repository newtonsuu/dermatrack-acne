import 'package:flutter/foundation.dart';

/// A dermatologist-authored prescription for a patient. Maps to a row in
/// `public.prescriptions` (migration 0008). A patient can have many over
/// time; each has free-text [body] instructions plus zero or more image
/// attachments stored in the `prescription-images` bucket.
@immutable
class Prescription {
  const Prescription({
    required this.id,
    required this.userId,
    required this.body,
    this.imagePaths = const [],
    this.imageUrls = const [],
    required this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// The patient this prescription is for.
  final String userId;
  final String body;

  /// Storage paths in the `prescription-images` bucket.
  final List<String> imagePaths;

  /// Signed display URLs, resolved by the service (parallel to [imagePaths];
  /// may be shorter if some failed to sign). Empty until resolved.
  final List<String> imageUrls;

  final DateTime createdAt;
  final DateTime? updatedAt;

  factory Prescription.fromRow(Map<String, dynamic> row) {
    final raw = row['image_paths'];
    final paths = raw is List
        ? raw.whereType<String>().toList(growable: false)
        : const <String>[];
    final updated = row['updated_at'] as String?;
    return Prescription(
      id: row['id'] as String,
      userId: row['user_id'] as String,
      body: (row['body'] as String?)?.trim() ?? '',
      imagePaths: paths,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      updatedAt: updated != null ? DateTime.parse(updated).toLocal() : null,
    );
  }

  Prescription copyWith({List<String>? imageUrls}) => Prescription(
        id: id,
        userId: userId,
        body: body,
        imagePaths: imagePaths,
        imageUrls: imageUrls ?? this.imageUrls,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
