import 'package:flutter/foundation.dart';

/// One chat message between a patient and the dermatologist. Maps to a row in
/// `public.messages` (migration 0009). [patientId] identifies the thread;
/// [senderRole] says who wrote it.
@immutable
class Message {
  const Message({
    required this.id,
    required this.patientId,
    required this.senderId,
    required this.senderRole,
    required this.body,
    required this.createdAt,
  });

  final String id;
  final String patientId;
  final String senderId;

  /// 'patient' or 'doctor'.
  final String senderRole;
  final String body;
  final DateTime createdAt;

  bool get isFromDoctor => senderRole == 'doctor';

  factory Message.fromRow(Map<String, dynamic> row) => Message(
        id: row['id'] as String,
        patientId: row['patient_id'] as String,
        senderId: row['sender_id'] as String,
        senderRole: (row['sender_role'] as String?) ?? 'patient',
        body: (row['body'] as String?) ?? '',
        createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      );
}
