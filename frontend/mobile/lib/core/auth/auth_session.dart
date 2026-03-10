import '../models/app_role.dart';

class AuthSession {
  const AuthSession({
    required this.token,
    required this.refreshToken,
    required this.userId,
    required this.phoneNumber,
    required this.displayName,
    required this.role,
  });

  final String token;
  final String refreshToken;
  final String userId;
  final String phoneNumber;
  final String displayName;
  final AppRole role;

  Map<String, String> toMap() {
    return {
      'token': token,
      'refreshToken': refreshToken,
      'userId': userId,
      'phoneNumber': phoneNumber,
      'displayName': displayName,
      'role': role.apiValue,
    };
  }

  static AuthSession? fromMap(Map<String, Object?> map) {
    final token = (map['token'] ?? '').toString().trim();
    final refreshToken = (map['refreshToken'] ?? '').toString().trim();
    final userId = (map['userId'] ?? '').toString().trim();
    final phoneNumber = (map['phoneNumber'] ?? '').toString().trim();
    final displayName = (map['displayName'] ?? '').toString().trim();
    final roleRaw = (map['role'] ?? '').toString().trim();

    if (token.isEmpty || refreshToken.isEmpty || userId.isEmpty || roleRaw.isEmpty) {
      return null;
    }

    return AuthSession(
      token: token,
      refreshToken: refreshToken,
      userId: userId,
      phoneNumber: phoneNumber,
      displayName: displayName,
      role: AppRole.fromApi(roleRaw),
    );
  }
}

