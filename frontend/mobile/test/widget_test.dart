import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wizgym/core/theme/app_theme.dart';
import 'package:wizgym/features/auth/role_selector_page.dart';

void main() {
  testWidgets('Role selector renders', (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: const RoleSelectorPage(),
      ),
    );

    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('WizGym'), findsOneWidget);
    expect(find.text('اختر دورك للبدء'), findsOneWidget);
  });
}
