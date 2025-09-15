// Golden-render capture for thesis screenshots.
//
// This is NOT a regression test — it exists to RENDER real app widgets to PNG
// files under thesis-docs/screenshots/ for the documentation. Run it with:
//
//   flutter test --update-goldens test/golden/capture_test.dart
//
// It loads a real system font (Segoe UI on Windows) so the captured text is
// legible instead of the placeholder boxes the default test font (Ahem)
// produces. The images are written relative to this file, up into the
// repo-root thesis-docs/screenshots/ folder.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dermatrack/screens/intro_welcome_screen.dart';
import 'package:dermatrack/theme/app_theme.dart';

/// Loads a real TTF under the family name [family] so golden renders show
/// actual glyphs. Falls back across a few common Windows font paths.
Future<void> _loadRealFont(String family) async {
  const candidates = [
    r'C:\Windows\Fonts\segoeui.ttf',
    r'C:\Windows\Fonts\arial.ttf',
    r'C:\Windows\Fonts\calibri.ttf',
  ];
  for (final path in candidates) {
    final file = File(path);
    if (file.existsSync()) {
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.view(bytes.buffer)));
      await loader.load();
      return;
    }
  }
}

/// Wraps [child] in a MaterialApp whose theme + DefaultTextStyle both use the
/// loaded font family, so every Text — themed Material widgets AND raw Text
/// with an explicit (family-less) style — renders with real glyphs.
Widget _framed(Widget child, {required String family}) {
  final base = AppTheme.light();
  // Material buttons render their label via ButtonStyle.textStyle, which
  // overrides any ambient DefaultTextStyle — so the family must be pushed into
  // the button themes too, or labels fall back to the box font.
  final labelStyle = WidgetStatePropertyAll(
    TextStyle(fontFamily: family, fontWeight: FontWeight.w600, fontSize: 15),
  );
  final theme = base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: family),
    primaryTextTheme: base.primaryTextTheme.apply(fontFamily: family),
    filledButtonTheme: FilledButtonThemeData(
      style: (base.filledButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: labelStyle),
    ),
    textButtonTheme: TextButtonThemeData(
      style: (base.textButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: labelStyle),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: (base.elevatedButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: labelStyle),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: (base.outlinedButtonTheme.style ?? const ButtonStyle())
          .copyWith(textStyle: labelStyle),
    ),
  );
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme,
    home: DefaultTextStyle.merge(
      style: TextStyle(fontFamily: family),
      child: child,
    ),
  );
}

void main() {
  const family = 'AppFont';

  setUpAll(() async {
    await _loadRealFont(family);
  });

  testWidgets('capture: welcome screen', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_framed(const IntroWelcomeScreen(), family: family));
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(IntroWelcomeScreen),
      matchesGoldenFile('../../../thesis-docs/screenshots/welcome_screen.png'),
    );
  });

  testWidgets('capture: logout confirmation prompt', (tester) async {
    tester.view.physicalSize = const Size(390, 360);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // Mirrors the AlertDialog shown by every sign-out path (admin/doctor/
    // patient settings). Rendered centered over a neutral surface.
    final dialog = AlertDialog(
      title: const Text('Sign out?'),
      content: const Text(
          "You'll leave the admin console and be returned to the welcome "
          'screen.'),
      actions: [
        TextButton(onPressed: () {}, child: const Text('Cancel')),
        FilledButton(onPressed: () {}, child: const Text('Sign out')),
      ],
    );

    await tester.pumpWidget(
      _framed(Center(child: dialog), family: family),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AlertDialog),
      matchesGoldenFile('../../../thesis-docs/screenshots/logout_prompt.png'),
    );
  });
}
