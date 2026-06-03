// Unit tests for ReminderFrequency parsing/persistence. The scan reminder
// stores its cadence as the enum's storageValue in SharedPreferences, so the
// round-trip and the unknown-value fallback must be stable.

import 'package:flutter_test/flutter_test.dart';
import 'package:dermatrack/services/scan_reminder_service.dart';

void main() {
  group('ReminderFrequency.fromStorage', () {
    test('maps known storage values', () {
      expect(ReminderFrequency.fromStorage('daily'), ReminderFrequency.daily);
      expect(ReminderFrequency.fromStorage('every_2_days'),
          ReminderFrequency.everyTwoDays);
      expect(ReminderFrequency.fromStorage('weekly'), ReminderFrequency.weekly);
    });

    test('defaults to daily for null / unknown', () {
      expect(ReminderFrequency.fromStorage(null), ReminderFrequency.daily);
      expect(ReminderFrequency.fromStorage('hourly'), ReminderFrequency.daily);
    });

    test('storageValue round-trips through fromStorage', () {
      for (final f in ReminderFrequency.values) {
        expect(ReminderFrequency.fromStorage(f.storageValue), f);
        expect(f.label, isNotEmpty);
      }
    });
  });
}
