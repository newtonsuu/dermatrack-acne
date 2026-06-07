// Widget tests for the DermaTrack auth flow.
//
// Flow: boot -> branded Welcome (IntroWelcomeScreen) -> "Get Started" ->
// "Login as" access selection -> role-themed LoginScreen. The patient login
// exposes Register + Forgot-password; doctor/admin logins hide the patient-only
// Register link. These run without Supabase — the auth gate falls back to the
// signed-out welcome flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dermatrack/main.dart';

/// Boots the app and advances past the branded welcome to the "Login as"
/// access-selection screen.
Future<void> bootToAccessSelection(WidgetTester tester) async {
  await tester.pumpWidget(const DermaTrackApp());
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('Get Started'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Get Started'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('App boots to the branded welcome screen', (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome to DermaTrack'), findsOneWidget);
    expect(find.text('Get Started'), findsOneWidget);
  });

  testWidgets('Get Started opens the "Login as" selection', (tester) async {
    await bootToAccessSelection(tester);

    expect(find.text('Login as'), findsOneWidget);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Doctor'), findsOneWidget);
    expect(find.text('Admin · Break-Glass'), findsOneWidget);
  });

  testWidgets('Patient access opens a login with Register + Forgot password',
      (tester) async {
    await bootToAccessSelection(tester);

    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2)); // email + password
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Register here'), findsOneWidget);
  });

  testWidgets('Doctor access opens a login WITHOUT the patient Register link',
      (tester) async {
    await bootToAccessSelection(tester);

    await tester.tap(find.text('Doctor'));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in to your Doctor account.'), findsOneWidget);
    expect(find.text('Register here'), findsNothing);
  });

  testWidgets('Patient login → "Register here" opens the register screen',
      (tester) async {
    await bootToAccessSelection(tester);
    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Register here'));
    await tester.tap(find.text('Register here'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(4));
  });

  testWidgets('Patient login → "Forgot password?" opens the reset screen',
      (tester) async {
    await bootToAccessSelection(tester);
    await tester.tap(find.text('Patient'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Forgot password?'));
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Send reset link'), findsOneWidget);
  });

  testWidgets('Login-as → "Create an account" opens the register screen',
      (tester) async {
    await bootToAccessSelection(tester);

    await tester.ensureVisible(find.text('Create an account'));
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
  });
}
