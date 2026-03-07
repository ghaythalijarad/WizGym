import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../app_new.dart';
import '../../core/auth/auth_session.dart';
import '../../core/auth/auth_session_store.dart';
import '../../core/config/app_config.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';

class RoleProfilePage extends StatefulWidget {
  const RoleProfilePage({
    super.key,
    required this.role,
    required this.session,
  });

  final AppRole role;
  final AuthSession? session;

  @override
  State<RoleProfilePage> createState() => _RoleProfilePageState();
}

class _RoleProfilePageState extends State<RoleProfilePage> {
  late Future<_ProfileData> _profileFuture;
  final AuthSessionStore _sessionStore = AuthSessionStore();

  @override
  void initState() {
    super.initState();
    _profileFuture = _loadProfile();
  }

  Uri _api(String path) {
    final base = AppConfig.apiBaseUrl.endsWith('/')
        ? AppConfig.apiBaseUrl
        : '${AppConfig.apiBaseUrl}/';
    return Uri.parse('$base$path');
  }

  Map<String, String> get _headers {
    final session = widget.session;
    return {
      'Content-Type': 'application/json',
      if (session?.token != null && session!.token.isNotEmpty)
        'Authorization': 'Bearer ${session.token}',
      'x-user-role':
          (session?.role.apiValue ?? widget.role.apiValue).toUpperCase(),
      'x-user-id': session?.userId ?? 'demo-user-id',
      'x-user-name':
          _sanitizeHeaderValue(session?.displayName ?? widget.role.labelAr),
    };
  }

  static String _sanitizeHeaderValue(String value) {
    return value.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  }

  Future<_ProfileData> _loadProfile() async {
    final response = await http.get(_api('users/me'), headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load profile: ${response.statusCode}');
    }

    final json = jsonDecode(response.body);
    if (json is! Map<String, dynamic>) {
      throw const FormatException('Invalid profile response');
    }

    return _ProfileData.fromJson(
      json,
      fallbackRole: widget.role,
      fallbackPhone: widget.session?.phoneNumber,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _profileFuture = _loadProfile();
    });
    await _profileFuture;
  }

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('حذف الحساب'),
          content: const Text(
            'سيتم حذف حسابك وبياناته المرتبطة نهائياً. هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError,
              ),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      final response = await http.delete(_api('users/me'), headers: _headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed: ${response.statusCode} ${response.body}');
      }

      await _sessionStore.clear();
      if (!mounted) return;

      // Restart to AuthGate.
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GymOsApp()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
    }
  }

  Future<void> _logout() async {
    await _sessionStore.clear();
    if (!mounted) return;

    // Restart to AuthGate.
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const GymOsApp()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<_ProfileData>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom + 80),
              children: [
                Text('الملف الشخصي',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: AppTheme.cardLime)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: AppTheme.cardPink.withValues(alpha: 0.10),
                    border: Border.all(
                      color: AppTheme.cardPink.withValues(alpha: 0.20),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'تعذر تحميل بيانات الملف من قاعدة البيانات.',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton(
                        onPressed: _reload,
                        child: const Text('إعادة المحاولة'),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          final data = snapshot.data!;
          const canDelete = true;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom + 80),
            children: [
              Text('الملف الشخصي',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: AppTheme.cardLime)),
              const SizedBox(height: 12),
              // ── Profile info with lavender accent ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: AppTheme.cardLavender.withValues(alpha: 0.10),
                  border: Border.all(
                    color: AppTheme.cardLavender.withValues(alpha: 0.20),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: AppTheme.cardLavender,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.person_rounded,
                              color: Color(0xFF1A1A24), size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data.displayName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: AppTheme.cardLavender)),
                              Text(data.roleLabel,
                                  style: const TextStyle(
                                      color: AppTheme.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _InfoRow(
                        label: 'رقم الهاتف', value: data.phoneNumber ?? '-'),
                    _InfoRow(label: 'معرف الحساب', value: data.id),
                    _InfoRow(
                        label: 'آخر تسجيل دخول',
                        value: data.lastLoginAt ?? '-'),
                    _InfoRow(
                        label: 'تاريخ الإنشاء', value: data.createdAt ?? '-'),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // ── Role capabilities with lime accent ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: AppTheme.cardLime.withValues(alpha: 0.08),
                  border: Border.all(
                    color: AppTheme.cardLime.withValues(alpha: 0.15),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('صلاحيات الدور',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppTheme.cardLime)),
                    const SizedBox(height: 8),
                    ..._roleCapabilities(data.role).map((item) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text('• $item',
                              style: const TextStyle(
                                  color: AppTheme.textSecondary)),
                        )),
                  ],
                ),
              ),
              if (canDelete) ...[
                const SizedBox(height: 12),
                // ── Logout with blue accent ──
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: Colors.blue.withValues(alpha: 0.08),
                    border: Border.all(
                      color: Colors.blue.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('الخروج من الحساب',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: Colors.blue)),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _logout,
                        icon: const Icon(Icons.logout),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                        label: const Text('تسجيل الخروج'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // ── Delete account with pink accent ──
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: AppTheme.cardPink.withValues(alpha: 0.08),
                    border: Border.all(
                      color: AppTheme.cardPink.withValues(alpha: 0.15),
                      width: 0.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('إدارة الحساب',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: AppTheme.cardPink)),
                      const SizedBox(height: 10),
                      FilledButton.icon(
                        onPressed: _deleteAccount,
                        icon: const Icon(Icons.delete_outline),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.cardPink,
                          foregroundColor: const Color(0xFF1A1A24),
                        ),
                        label: const Text('حذف الحساب نهائياً'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }

  List<String> _roleCapabilities(AppRole role) {
    switch (role) {
      case AppRole.owner:
        return const [
          'إدارة بيانات النادي والخدمات',
          'إضافة المرافق والمنتجات',
          'متابعة الاشتراكات والتحليلات',
        ];
      case AppRole.trainer:
        return const [
          'الانضمام لنوادي بحد أقصى 4',
          'متابعة العملاء النشطين',
          'إدارة خطة التدريب اليومية',
        ];
      case AppRole.trainee:
        return const [
          'استكشاف النوادي والانضمام',
          'توظيف المدربين وتقييمهم',
          'متابعة الاشتراك والتمارين',
        ];
      case AppRole.user:
        return const [
          'استكشاف النوادي والانضمام',
          'توظيف المدربين وتقييمهم',
          'متابعة الاشتراك والتمارين',
        ];
      case AppRole.admin:
        return const [
          'إدارة المنصة والمستخدمين',
          'اعتماد النوادي والإشراف',
          'مراجعة التقارير والتدقيق',
        ];
    }
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style: textTheme.titleMedium
                    ?.copyWith(color: AppTheme.textSecondary)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              textAlign: TextAlign.left,
              textDirection: TextDirection.ltr,
              style:
                  textTheme.bodyMedium?.copyWith(color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileData {
  const _ProfileData({
    required this.id,
    required this.displayName,
    required this.role,
    required this.roleLabel,
    this.phoneNumber,
    this.createdAt,
    this.lastLoginAt,
  });

  final String id;
  final String displayName;
  final AppRole role;
  final String roleLabel;
  final String? phoneNumber;
  final String? createdAt;
  final String? lastLoginAt;

  factory _ProfileData.fromJson(
    Map<String, dynamic> json, {
    required AppRole fallbackRole,
    required String? fallbackPhone,
  }) {
    final role =
        AppRole.fromApi((json['role'] ?? fallbackRole.apiValue).toString());
    return _ProfileData(
      id: (json['id'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      phoneNumber: json['phoneNumber']?.toString() ?? fallbackPhone,
      createdAt: _toHumanDate(json['createdAt']?.toString()),
      lastLoginAt: _toHumanDate(json['lastLoginAt']?.toString()),
      role: role,
      roleLabel: role.labelAr,
    );
  }

  static String? _toHumanDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    final local = parsed.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}
