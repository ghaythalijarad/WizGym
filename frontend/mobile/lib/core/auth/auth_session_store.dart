import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session.dart';

/// Stores auth session credentials in platform-secure storage
/// (iOS Keychain / Android EncryptedSharedPreferences).
///
/// On first run after upgrade, migrates any existing plaintext
/// SharedPreferences values then deletes them.
class AuthSessionStore {
  static const _prefix = 'auth.session.';
  static const _keys = [
    'token',
    'refreshToken',
    'userId',
    'phoneNumber',
    'displayName',
    'role',
  ];

  final FlutterSecureStorage _secure = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<AuthSession?> load() async {
    // ── One-time migration from SharedPreferences ──────────────────
    await _migrateFromSharedPreferences();

    final map = <String, Object?>{};
    for (final key in _keys) {
      map[key] = await _secure.read(key: '$_prefix$key');
    }
    return AuthSession.fromMap(map);
  }

  Future<void> save(AuthSession session) async {
    final data = session.toMap();
    for (final key in _keys) {
      await _secure.write(key: '$_prefix$key', value: data[key]!);
    }
  }

  Future<void> clear() async {
    for (final key in _keys) {
      await _secure.delete(key: '$_prefix$key');
    }
  }

  // ── Migration helper ─────────────────────────────────────────────
  static const _migratedKey = '${_prefix}migrated_to_secure';

  Future<void> _migrateFromSharedPreferences() async {
    final already = await _secure.read(key: _migratedKey);
    if (already == 'true') return;

    final prefs = await SharedPreferences.getInstance();
    bool hadData = false;

    for (final key in _keys) {
      final value = prefs.getString('$_prefix$key');
      if (value != null && value.isNotEmpty) {
        await _secure.write(key: '$_prefix$key', value: value);
        await prefs.remove('$_prefix$key');
        hadData = true;
      }
    }

    if (hadData) {
      // ignore: avoid_print
      print('[AuthSessionStore] Migrated session from SharedPreferences → SecureStorage');
    }

    await _secure.write(key: _migratedKey, value: 'true');
  }
}

