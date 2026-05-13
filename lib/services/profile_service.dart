import 'package:flutter/foundation.dart';

import '../models/scan.dart';

/// In-memory profile + scan history store.
///
/// v1 — local only. Swap for Supabase Storage (profile picture) and a `scans`
/// table (history) in week 2 while keeping the same public surface.
class ProfileService extends ChangeNotifier {
  ProfileService._internal() {
    _scans = _generateMockScans();
  }
  static final ProfileService instance = ProfileService._internal();

  String? _profilePicturePath;
  String? get profilePicturePath => _profilePicturePath;

  late final List<Scan> _scans;

  /// All scans, most recent first.
  List<Scan> get scans => List.unmodifiable(_scans);

  /// Most recent [count] scans, newest first.
  List<Scan> recentScans({int count = 6}) =>
      _scans.take(count).toList(growable: false);

  Future<void> setProfilePicture(String path) async {
    _profilePicturePath = path;
    notifyListeners();
  }

  Future<void> clearProfilePicture() async {
    _profilePicturePath = null;
    notifyListeners();
  }

  /// Realistic-looking mock data showing a downward severity trend over two
  /// weeks. Replace with real Supabase queries in week 2.
  List<Scan> _generateMockScans() {
    final now = DateTime.now();
    // (daysAgo, cookGrade)
    const samples = [
      (1, 3),
      (3, 4),
      (5, 4),
      (8, 5),
      (11, 6),
      (14, 6),
    ];
    return [
      for (final s in samples)
        Scan(
          id: 'mock_${s.$1}',
          takenAt: now.subtract(Duration(days: s.$1)),
          cookGrade: s.$2,
        ),
    ];
  }
}
