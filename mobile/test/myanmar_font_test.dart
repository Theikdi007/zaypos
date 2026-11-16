// Android round: Burmese text must always use the bundled Unicode font
// (Noto Sans Myanmar), never the phone's system Myanmar font, which on many
// Android phones in Myanmar is Zawgyi and would garble Unicode text.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaypos_app/core/theme/app_text.dart';
import 'package:zaypos_app/core/theme/app_theme.dart';

void main() {
  final theme = AppTheme.light();

  Map<String, TextStyle?> slots(TextTheme t) => {
        'displayLarge': t.displayLarge,
        'displayMedium': t.displayMedium,
        'displaySmall': t.displaySmall,
        'headlineLarge': t.headlineLarge,
        'headlineMedium': t.headlineMedium,
        'headlineSmall': t.headlineSmall,
        'titleLarge': t.titleLarge,
        'titleMedium': t.titleMedium,
        'titleSmall': t.titleSmall,
        'bodyLarge': t.bodyLarge,
        'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall,
        'labelLarge': t.labelLarge,
        'labelMedium': t.labelMedium,
        'labelSmall': t.labelSmall,
      };

  for (final (name, t) in [('textTheme', theme.textTheme), ('primaryTextTheme', theme.primaryTextTheme)]) {
    test('$name: every slot uses Inter with the bundled Noto Sans Myanmar fallback', () {
      slots(t).forEach((slot, style) {
        expect(style, isNotNull, reason: '$name.$slot');
        expect(style!.fontFamily, AppText.inter, reason: '$name.$slot');
        expect(style.fontFamilyFallback, contains(AppText.myanmar), reason: '$name.$slot');
      });
    });
  }

  test('AppText.s uses the bundled fonts', () {
    final s = AppText.s(14);
    expect(s.fontFamily, AppText.inter);
    expect(s.fontFamilyFallback, [AppText.myanmar]);
  });

  test('pubspec bundles the Noto Sans Myanmar asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: ${AppText.myanmar}'));
    expect(pubspec, contains('assets/fonts/NotoSansMyanmar-Variable.ttf'));
    final font = File('assets/fonts/NotoSansMyanmar-Variable.ttf');
    expect(font.existsSync(), isTrue);
    expect(font.lengthSync(), greaterThan(50 * 1024));
  });

  testWidgets('unstyled Text and a date picker inherit the bundled fonts', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => Scaffold(
          body: Column(children: [
            const Text('မင်္ဂလာပါ'),
            TextButton(
              onPressed: () => showDatePicker(
                context: context,
                firstDate: DateTime(2026),
                lastDate: DateTime(2027),
                initialDate: DateTime(2026, 11, 16),
              ),
              child: const Text('date'),
            ),
          ]),
        ),
      ),
    ));
    final plain = tester.widget<RichText>(find.descendant(of: find.text('မင်္ဂလာပါ'), matching: find.byType(RichText)));
    expect(plain.text.style!.fontFamily, AppText.inter);
    expect(plain.text.style!.fontFamilyFallback, contains(AppText.myanmar));

    await tester.tap(find.text('date'));
    await tester.pumpAndSettle();
    final texts = tester.widgetList<RichText>(find.descendant(of: find.byType(DatePickerDialog), matching: find.byType(RichText)));
    expect(texts, isNotEmpty);
    for (final t in texts) {
      final style = t.text.style;
      if (style == null || style.fontFamily == 'MaterialIcons') continue;
      expect(style.fontFamily, AppText.inter, reason: t.text.toPlainText());
      expect(style.fontFamilyFallback, contains(AppText.myanmar), reason: t.text.toPlainText());
    }
  });
}
