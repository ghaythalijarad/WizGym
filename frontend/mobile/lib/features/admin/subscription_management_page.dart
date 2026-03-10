import 'package:flutter/material.dart';

// NOTE: Admin pages are currently not shipped in the mobile app bundle.
// We keep this file as a placeholder, but guard it so it doesn't require
// missing dependencies during development.
const bool _kEnableAdminPages = bool.fromEnvironment(
  'ENABLE_ADMIN_PAGES',
  defaultValue: false,
);

class SubscriptionManagementPage extends StatelessWidget {
  const SubscriptionManagementPage({super.key});

  @override
  Widget build(BuildContext context) {
    if (!_kEnableAdminPages) {
      return const _AdminDisabledPlaceholder();
    }

    // If/when admin pages are enabled, restore the original implementation.
    return const _AdminDisabledPlaceholder();
  }
}

class _AdminDisabledPlaceholder extends StatelessWidget {
  const _AdminDisabledPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'صفحات الإدارة غير مفعّلة في نسخة الموبايل حالياً.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
