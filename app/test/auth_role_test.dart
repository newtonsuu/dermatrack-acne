// Unit tests for role parsing. AuthService routes admin → AdminShell,
// doctor → DoctorShell, patient → HomeShell based on this mapping, and an
// unknown/missing role must never silently escalate — it defaults to patient.

import 'package:flutter_test/flutter_test.dart';
import 'package:dermatrack/services/auth_service.dart';

void main() {
  group('userRoleFromString', () {
    test('maps known roles', () {
      expect(userRoleFromString('admin'), UserRole.admin);
      expect(userRoleFromString('doctor'), UserRole.doctor);
      expect(userRoleFromString('patient'), UserRole.patient);
    });

    test('defaults to patient for null / empty / unknown (no escalation)', () {
      expect(userRoleFromString(null), UserRole.patient);
      expect(userRoleFromString(''), UserRole.patient);
      expect(userRoleFromString('superuser'), UserRole.patient);
      expect(userRoleFromString('Admin'), UserRole.patient); // case-sensitive
    });
  });
}
