import 'dart:async';

import 'package:flutter/material.dart';

import 'core/auth/auth_events.dart';
import 'core/auth/auth_session.dart';
import 'core/auth/auth_session_store.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_gate_page.dart';
import 'features/splash/splash_page.dart';
import 'shared/widgets/role_shell.dart';
import 'core/localization/app_locale_controller.dart';
import 'l10n/app_localizations.dart';

class GymOsApp extends StatefulWidget {
  const GymOsApp({super.key});

  @override
  State<GymOsApp> createState() => _GymOsAppState();
}

class _GymOsAppState extends State<GymOsApp> {
  bool _showSplash = true;
  bool _sessionLoaded = false;
  AuthSession? _session;
  final AuthSessionStore _sessionStore = AuthSessionStore();
  final AppLocaleController _localeController = AppLocaleController();
  StreamSubscription<void>? _authSub;

  @override
  void initState() {
    super.initState();
    _authSub = AuthEvents.onUnauthorized.listen((_) => _onLogout());
    _restoreSession();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _localeController.dispose();
    super.dispose();
  }

  Future<void> _restoreSession() async {
    final restored = await _sessionStore.load();
    if (!mounted) return;
    // Start notification polling with the restored session (may be null = not logged in yet)
    await NotificationService.instance.init(restored);
    setState(() {
      _session = restored;
      _sessionLoaded = true;
    });
  }

  void _dismissSplash() {
    setState(() {
      _showSplash = false;
    });
  }

  Future<void> _onAuthenticated(AuthSession session) async {
    await _sessionStore.save(session);
    // Re-init notifications with the fresh session so polling uses real auth token
    await NotificationService.instance.init(session);
    if (!mounted) return;
    setState(() {
      _session = session;
    });
  }

  Future<void> _onLogout() async {
    await _sessionStore.clear();
    NotificationService.instance.init(null); // stop polling, clear session
    if (!mounted) return;
    setState(() {
      _session = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showSplash = _showSplash || !_sessionLoaded;

    return AnimatedBuilder(
      animation: _localeController,
      builder: (context, _) {
        final locale = _localeController.locale;
        final isArabic = locale.languageCode.toLowerCase() == 'ar';

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: locale,
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          builder: (context, child) {
            return Directionality(
              textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
              child: child ?? const SizedBox.shrink(),
            );
          },
          title: 'GymOS',
          theme: AppTheme.lightTheme,
          home: showSplash
              ? SplashPage(onFinished: _dismissSplash)
              : (_session != null
                  ? RoleShell(
                      role: _session!.role,
                      onLogout: _onLogout,
                      session: _session,
                    )
                  : AuthGatePage(
                      onAuthenticated: _onAuthenticated,
                      localeController: _localeController,
                    )),
        );
      },
    );
  }
}
