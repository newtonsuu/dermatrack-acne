// Widget tests for the DermaTrack auth flow.
//
// The entry screen is the "Login as" access-type selection (Patient / Doctor /
// Admin · Break-Glass). Picking a role opens a themed LoginScreen; the patient
// login exposes Register + Forgot-password, while the doctor/admin logins hide
// the patient-only Register link. These tests run without Supabase — the auth
// gate falls back to the signed-out WelcomeScreen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dermatrack/main.dart';

void main() {
  testWidgets('App boots to the "Login as" access selection', (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    expect(find.text('Login as'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Admin · Break-Glass'), findsOneWidget);
  });

  testWidgets('Patient access opens a login with Register + Forgot password',
      (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    // email + password
    expect(find.byType(TextFormField), findsNWidgets(2));
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Register here'), findsOneWidget);
  });

  testWidgets('Doctor access opens a login WITHOUT the patient Register link',
      (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to your Doctor account.'), findsOneWidget);
    // Register is patient-only; it must not appear on the doctor login.
    expect(find.text('Register here'), findsNothing);
  });

  testWidgets('Patient login → "Register here" opens the register screen',
      (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Register here'));
    await tester.tap(find.text('Register here'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    // email + username + password + confirm
    expect(find.byType(TextFormField), findsNWidgets(4));
  });

  testWidgets('Patient login → "Forgot password?" opens the reset screen',
      (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Send reset link'), findsOneWidget);
  });

  testWidgets('Boot → "Create an account" opens the register screen',
      (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
  });
}
