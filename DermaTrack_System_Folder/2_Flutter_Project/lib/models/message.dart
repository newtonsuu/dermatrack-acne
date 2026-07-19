import 'package:flutter/foundation.dart';

/// One chat message between a patient and the dermatologist. Maps to a row in
/// `public.messages` (migration 0009; edit/unsend + moderation in 0012).
/// [patientId] identifies the thread; [senderRole] says who wrote it.
@immutable
class Message {
  const Message({
    required this.id,
    required this.patientId,
    required this.senderId,
    required this.senderRole,
    required this.body,
    required this.createdAt,
    this.editedAt,
    this.deletedAt,
    this.removedByAdmin = false,
  });

  final String id;
  final String patientId;
  final String senderId;

  /// 'patient' or 'doctor'.
  final String senderRole;
  final String body;
  final DateTime createdAt;

  /// Set when the sender edited the message.
  final DateTime? editedAt;

  /// Set when unsent (soft delete). Body is hidden in normal UI.
  final DateTime? deletedAt;

  /// True when a moderator/admin removed the message.
  final bool removedByAdmin;

  bool get isFromDoctor => senderRole == 'doctor';

  /// Whether this message was unsent (by the sender) or removed (by an admin).
  bool get isUnsent => deletedAt != null || removedByAdmin;

  /// Whether to show the "edited" marker (edited and not unsent).
  bool get isEdited => editedAt != null && !isUnsent;

  factory Message.fromRow(Map<String, dynamic> row) => Message(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        senderId: row['sender_id'] as String,
        senderRole: (row['sender_role'] as String?) ?? 'patient',
        body: (row['body'] as String?) ?? '',
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
        editedAt: row['edited_at'] != null
            ? DateTime.tryParse(row['edited_at'] as String)?.toLocal()
            : null,
        deletedAt: row['deleted_at'] != null
            ? DateTime.tryParse(row['deleted_at'] as String)?.toLocal()
            : null,
        removedByAdmin: (row['removed_by_admin'] as bool?) ?? false,
      );
}
