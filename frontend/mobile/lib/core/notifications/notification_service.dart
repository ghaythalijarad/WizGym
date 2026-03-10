import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../auth/auth_session.dart';
import '../config/app_config.dart';
import 'notification_model.dart';

/// Singleton service — call [NotificationService.instance] everywhere.
class NotificationService extends ChangeNotifier {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  static const _prefsKey = 'app_notifications_v1';
  static const _pollInterval = Duration(seconds: 30);

  final List<AppNotification> _notifications = [];
  Timer? _pollTimer;
  AuthSession? _session;
  bool _initialized = false;

  // ── Public API ────────────────────────────────────────────────────────────

  List<AppNotification> get notifications => List.unmodifiable(_notifications);

  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  /// Call once after login / session restore.
  Future<void> init(AuthSession? session) async {
    _session = session;
    if (_initialized) {
      // session may have changed; restart poll
      _startPolling();
      return;
    }
    _initialized = true;
    await _loadFromPrefs();
    _startPolling();
  }

  /// Mark a single notification as read.
  Future<void> markRead(String id) async {
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    _notifications[idx] = _notifications[idx].copyWith(isRead: true);
    notifyListeners();
    await _saveToPrefs();
  }

  /// Mark all as read.
  Future<void> markAllRead() async {
    for (int i = 0; i < _notifications.length; i++) {
      _notifications[i] = _notifications[i].copyWith(isRead: true);
    }
    notifyListeners();
    await _saveToPrefs();
  }

  /// Clear all notifications.
  Future<void> clearAll() async {
    _notifications.clear();
    notifyListeners();
    await _saveToPrefs();
  }

  /// Add a local notification (e.g., triggered by an app event).
  Future<void> addLocal(AppNotification notification) async {
    _notifications.insert(0, notification);
    notifyListeners();
    await _saveToPrefs();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Polling ───────────────────────────────────────────────────────────────

  void _startPolling() {
    _pollTimer?.cancel();
    _fetchRemote(); // immediate first fetch
    _pollTimer = Timer.periodic(_pollInterval, (_) => _fetchRemote());
  }

  Future<void> _fetchRemote() async {
    final session = _session;
    if (session == null) return;

    try {
      final base = _normalizeBase(AppConfig.apiBaseUrl);
      final uri = Uri.parse('${base}notifications');
      final response = await http
          .get(uri, headers: _headers(session))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) return;

      final body = jsonDecode(response.body);
      final List<dynamic> items = body is List
          ? body
          : (body is Map && body['notifications'] is List)
              ? body['notifications'] as List
              : [];

      bool changed = false;
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final notification = AppNotification.fromApiEvent(item);
        final exists = _notifications.any((n) => n.id == notification.id);
        if (!exists) {
          _notifications.insert(0, notification);
          changed = true;
        }
      }

      // Keep max 100 notifications
      if (_notifications.length > 100) {
        _notifications.removeRange(100, _notifications.length);
        changed = true;
      }

      if (changed) {
        notifyListeners();
        await _saveToPrefs();
      }
    } catch (_) {
      // Silently ignore network errors — offline mode is fine
    }
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      final list = jsonDecode(raw) as List<dynamic>;
      _notifications.addAll(
        list.whereType<Map<String, dynamic>>().map(AppNotification.fromJson),
      );
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsKey,
        jsonEncode(_notifications.map((n) => n.toJson()).toList()),
      );
    } catch (_) {}
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, String> _headers(AuthSession s) => {
        'Content-Type': 'application/json',
        if (s.token.isNotEmpty) 'Authorization': 'Bearer ${s.token}',
        'x-user-role': s.role.apiValue.toUpperCase(),
        'x-user-id': s.userId,
        'x-user-name': _sanitize(s.displayName),
      };

  static String _sanitize(String v) =>
      Uri.encodeComponent(v.trim()); // URI-encode so Arabic survives HTTP headers

  static String _normalizeBase(String url) => url.endsWith('/') ? url : '$url/';
}
