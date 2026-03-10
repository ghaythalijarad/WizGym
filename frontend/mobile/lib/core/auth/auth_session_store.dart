import 'package:shared_preferences/shared_preferences.dart';

import 'auth_session.dart';

class AuthSessionStore {
  static const _prefix = 'auth.session.';

  Future<AuthSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, Object?>{
      'token': prefs.getString('${_prefix}token'),
      'refreshToken': prefs.getString('${_prefix}refreshToken'),
      'userId': prefs.getString('${_prefix}userId'),
      'phoneNumber': prefs.getString('${_prefix}phoneNumber'),
      'displayName': prefs.getString('${_prefix}displayName'),
      'role': prefs.getString('${_prefix}role'),
    };
    return AuthSession.fromMap(map);
  }

  Future<void> save(AuthSession session) async {
    final prefs = await SharedPreferences.getInstance();
    final data = session.toMap();
    await prefs.setString('${_prefix}token', data['token']!);
    await prefs.setString('${_prefix}refreshToken', data['refreshToken']!);
    await prefs.setString('${_prefix}userId', data['userId']!);
    await prefs.setString('${_prefix}phoneNumber', data['phoneNumber']!);
    await prefs.setString('${_prefix}displayName', data['displayName']!);
    await prefs.setString('${_prefix}role', data['role']!);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('${_prefix}token');
    await prefs.remove('${_prefix}refreshToken');
    await prefs.remove('${_prefix}userId');
    await prefs.remove('${_prefix}phoneNumber');
    await prefs.remove('${_prefix}displayName');
    await prefs.remove('${_prefix}role');
  }
}

