import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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
  bool _isUploadingAvatar = false;
  bool _isSavingBio = false;

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
          Uri.encodeComponent(
          (session?.displayName ?? widget.role.labelAr).trim()),
    };
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
    final next = _loadProfile();
    setState(() => _profileFuture = next);
    await next;
  }

  // ── Avatar upload ────────────────────────────────────────────────────────

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 800,
    );
    if (picked == null || !mounted) return;

    setState(() => _isUploadingAvatar = true);
    try {
      final file = File(picked.path);
      final ext = picked.path.split('.').last.toLowerCase();
      final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';

      // 1. Get presigned PUT URL
      final presignRes = await http.post(
        _api('users/me/avatar/presign'),
        headers: _headers,
        body: jsonEncode({'contentType': contentType}),
      );
      if (presignRes.statusCode != 200) {
        throw Exception('فشل في الحصول على رابط الرفع');
      }
      final presignData = jsonDecode(presignRes.body) as Map<String, dynamic>;
      final uploadUrl = presignData['uploadUrl'] as String;
      final objectKey = presignData['objectKey'] as String;

      // 2. Upload directly to S3
      final bytes = await file.readAsBytes();
      final uploadRes = await http.put(
        Uri.parse(uploadUrl),
        headers: {'Content-Type': contentType},
        body: bytes,
      );
      if (uploadRes.statusCode != 200) {
        throw Exception('فشل رفع الصورة إلى S3');
      }

      // 3. Confirm with backend
      final confirmRes = await http.patch(
        _api('users/me/avatar'),
        headers: _headers,
        body: jsonEncode({'objectKey': objectKey}),
      );
      if (confirmRes.statusCode != 200) {
        throw Exception('فشل تأكيد الصورة');
      }

      if (!mounted) return;
      _showMessage('تم تحديث الصورة الشخصية ✓');
      _reload();
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  Future<void> _removeAvatar() async {
    setState(() => _isUploadingAvatar = true);
    try {
      await http.delete(_api('users/me/avatar'), headers: _headers);
      if (!mounted) return;
      _showMessage('تم حذف الصورة الشخصية');
      _reload();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isUploadingAvatar = false);
    }
  }

  // ── Bio edit ─────────────────────────────────────────────────────────────

  Future<void> _editBio(String currentBio) async {
    final ctrl = TextEditingController(text: currentBio);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16162A),
        title: const Text('تعديل النبذة الشخصية',
            style:
                TextStyle(color: AppTheme.gold, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          maxLength: 500,
          textDirection: TextDirection.rtl,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: InputDecoration(
            hintText: 'اكتب نبذة مختصرة عنك كمدرب...',
            hintStyle: const TextStyle(color: AppTheme.textMuted),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: AppTheme.gold.withValues(alpha: 0.3)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: AppTheme.gold.withValues(alpha: 0.2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppTheme.gold),
            ),
            filled: true,
            fillColor: const Color(0xFF0D0D1A),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            style: FilledButton.styleFrom(backgroundColor: AppTheme.gold),
            child: const Text('حفظ', style: TextStyle(color: AppTheme.black)),
          ),
        ],
      ),
    );

    if (result == null || !mounted) return;
    setState(() => _isSavingBio = true);
    try {
      final res = await http.patch(
        _api('users/me/profile'),
        headers: _headers,
        body: jsonEncode({'bio': result}),
      );
      if (res.statusCode != 200) throw Exception('فشل الحفظ');
      if (!mounted) return;
      _showMessage('تم حفظ النبذة ✓');
      _reload();
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString());
    } finally {
      if (mounted) setState(() => _isSavingBio = false);
    }
  }

  // ── Account actions ───────────────────────────────────────────────────────

  Future<void> _deleteAccount() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
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
      ),
    );
    if (ok != true) return;
    try {
      final response = await http.delete(_api('users/me'), headers: _headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed: ${response.statusCode} ${response.body}');
      }
      await _sessionStore.clear();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const GymOsApp()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _logout() async {
    await _sessionStore.clear();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const GymOsApp()),
      (route) => false,
    );
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: _reload,
      child: FutureBuilder<_ProfileData>(
        future: _profileFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.gold),
            );
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              children: [
                const _PageHeader(label: 'الملف الشخصي'),
                const SizedBox(height: 16),
                _PremiumCard(
                  accentColor: scheme.error,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('تعذر تحميل البيانات',
                          style: tt.titleSmall
                              ?.copyWith(color: scheme.onErrorContainer)),
                      const SizedBox(height: 10),
                      FilledButton(
                          onPressed: _reload,
                          child: const Text('إعادة المحاولة')),
                    ],
                  ),
                ),
              ],
            );
          }

          final data = snapshot.data!;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
            children: [
              const _PageHeader(label: 'الملف الشخصي'),
              const SizedBox(height: 20),

              // ── Avatar + name card ───────────────────────────────────────
              _PremiumCard(
                accentColor: AppTheme.gold,
                child: Row(
                  children: [
                    // Avatar with tap to change
                    GestureDetector(
                      onTap: _pickAndUploadAvatar,
                      child: Stack(
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              gradient: data.avatarUrl == null
                                  ? const LinearGradient(
                                      colors: [
                                        AppTheme.goldDeep,
                                        AppTheme.gold
                                      ],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    )
                                  : null,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: AppTheme.gold.withValues(alpha: 0.4),
                                  width: 2),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: data.avatarUrl != null
                                ? Image.network(
                                    data.avatarUrl!,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, __, ___) => const Icon(
                                        Icons.person_rounded,
                                        color: AppTheme.black,
                                        size: 36),
                                  )
                                : const Icon(Icons.person_rounded,
                                    color: AppTheme.black, size: 36),
                          ),
                          Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: AppTheme.gold,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: _isUploadingAvatar
                                    ? const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: AppTheme.black),
                                      )
                                    : const Icon(Icons.camera_alt_rounded,
                                        size: 14, color: AppTheme.black),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data.displayName,
                              style: tt.titleMedium?.copyWith(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w800,
                              )),
                          const SizedBox(height: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppTheme.goldDeep,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(data.roleLabel,
                                style: tt.labelSmall?.copyWith(
                                  color: AppTheme.goldLight,
                                  fontWeight: FontWeight.w700,
                                )),
                          ),
                          if (data.avatarUrl != null) ...[
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: _removeAvatar,
                              child: Text('حذف الصورة',
                                  style: tt.labelSmall
                                      ?.copyWith(color: scheme.error)),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ── Phone ────────────────────────────────────────────────────
              if (data.phoneNumber != null && data.phoneNumber!.isNotEmpty) ...[
                const SizedBox(height: 10),
                _PremiumCard(
                  accentColor: AppTheme.gold,
                  child: Row(
                    children: [
                      const Icon(Icons.phone_outlined,
                          size: 18, color: AppTheme.gold),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(data.phoneNumber!,
                            style: tt.bodyMedium?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                            textDirection: TextDirection.ltr),
                      ),
                      Text('رقم الهاتف',
                          style: tt.labelSmall
                              ?.copyWith(color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ],

              // ── Bio (trainer only) ────────────────────────────────────────
              if (widget.role == AppRole.trainer) ...[
                const SizedBox(height: 10),
                _PremiumCard(
                  accentColor: AppTheme.gold,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.notes_rounded,
                              size: 18, color: AppTheme.gold),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('النبذة الشخصية',
                                style: tt.labelMedium
                                    ?.copyWith(color: AppTheme.textSecondary)),
                          ),
                          GestureDetector(
                            onTap: _isSavingBio
                                ? null
                                : () => _editBio(data.bio ?? ''),
                            child: _isSavingBio
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: AppTheme.gold),
                                  )
                                : const Icon(Icons.edit_outlined,
                                    size: 18, color: AppTheme.gold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        data.bio != null && data.bio!.isNotEmpty
                            ? data.bio!
                            : 'اضغط على ✏️ لإضافة نبذة عنك...',
                        style: tt.bodyMedium?.copyWith(
                          color: data.bio != null && data.bio!.isNotEmpty
                              ? AppTheme.textPrimary
                              : AppTheme.textMuted,
                          height: 1.55,
                        ),
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 28),
              const _SectionDivider(label: 'الحساب'),
              const SizedBox(height: 14),

              // ── Logout ───────────────────────────────────────────────────
              _PremiumCard(
                accentColor: AppTheme.gold,
                child: FilledButton.icon(
                  onPressed: _logout,
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: const Text('تسجيل الخروج'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // ── Delete account ───────────────────────────────────────────
              _PremiumCard(
                accentColor: scheme.error,
                child: FilledButton.icon(
                  onPressed: _deleteAccount,
                  icon: const Icon(Icons.delete_forever_outlined, size: 18),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  label: const Text('حذف الحساب نهائياً'),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium card widget
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumCard extends StatelessWidget {
  const _PremiumCard({required this.child, required this.accentColor});
  final Widget child;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: accentColor.withValues(alpha: 0.22), width: 1),
      ),
      child: child,
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            color: AppTheme.gold,
            fontWeight: FontWeight.w800,
          ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child:
              Divider(height: 1, color: Theme.of(context).colorScheme.outline),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.textMuted,
                    letterSpacing: 0.8,
                  )),
        ),
        Expanded(
          child:
              Divider(height: 1, color: Theme.of(context).colorScheme.outline),
        ),
      ],
    );
  }
}

class _ProfileData {
  const _ProfileData({
    required this.displayName,
    required this.role,
    required this.roleLabel,
    this.phoneNumber,
    this.bio,
    this.avatarUrl,
  });

  final String displayName;
  final AppRole role;
  final String roleLabel;
  final String? phoneNumber;
  final String? bio;
  final String? avatarUrl;

  factory _ProfileData.fromJson(
    Map<String, dynamic> json, {
    required AppRole fallbackRole,
    required String? fallbackPhone,
  }) {
    final role =
        AppRole.fromApi((json['role'] ?? fallbackRole.apiValue).toString());
    final bioRaw = json['bio']?.toString();
    return _ProfileData(
      displayName: (json['displayName'] ?? '').toString(),
      phoneNumber: json['phoneNumber']?.toString() ?? fallbackPhone,
      role: role,
      roleLabel: role.labelAr,
      bio: (bioRaw != null && bioRaw.isNotEmpty) ? bioRaw : null,
      avatarUrl: json['avatarUrl']?.toString(),
    );
  }
}
