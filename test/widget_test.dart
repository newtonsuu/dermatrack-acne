// Basic widget tests for DermaTrack auth flow.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dermatrack/main.dart';

void main() {
  testWidgets('App boots and shows the login screen', (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Sign in'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2)); // email + password
    expect(find.text('Forgot password?'), findsOneWidget);
    expect(find.text('Register here'), findsOneWidget);
  });

  testWidgets('Tapping "Register here" navigates to the register screen',
      (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Register here'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    // email + username + password + confirm password = 4 fields
    expect(find.byType(TextFormField), findsNWidgets(4));
    expect(find.text('Password must include:'), findsOneWidget);
  });

  testWidgets('Tapping "Forgot password?" navigates to reset screen',
      (tester) async {
    await tester.pumpWidget(const DermaTrackApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(find.text('Forgot your password?'), findsOneWidget);
    expect(find.text('Send reset link'), findsOneWidget);
  });
}
