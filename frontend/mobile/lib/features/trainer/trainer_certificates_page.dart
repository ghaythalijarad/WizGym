import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../marketplace/marketplace_api_service.dart';

class TrainerCertificatesPage extends StatefulWidget {
  const TrainerCertificatesPage({super.key, required this.session});

  final AuthSession? session;

  @override
  State<TrainerCertificatesPage> createState() =>
      _TrainerCertificatesPageState();
}

class _TrainerCertificatesPageState extends State<TrainerCertificatesPage> {
  static const int _maxItems = 5;

  late final MarketplaceApiService _api;
  final ImagePicker _picker = ImagePicker();

  bool _busy = false;
  late Future<List<Map<String, dynamic>>> _itemsFuture;

  File? _pickedImage;
  String? _pickedMime;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _yearController = TextEditingController();
  final TextEditingController _descController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _api =
        MarketplaceApiService(role: AppRole.trainer, session: widget.session);
    _itemsFuture = _api.fetchMyTrainerCertificatesRaw();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _yearController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    setState(() {
      _itemsFuture = _api.fetchMyTrainerCertificatesRaw();
    });
  }

  String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _pickImage(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 2000,
    );
    if (picked == null) return;

    setState(() {
      _pickedImage = File(picked.path);
      _pickedMime = _guessMime(picked.path);
    });
  }

  Future<void> _submit() async {
    if (_busy) return;

    final name = _nameController.text.trim();
    final year = int.tryParse(_yearController.text.trim());
    final desc = _descController.text.trim();
    final file = _pickedImage;
    final mime = _pickedMime;

    if (name.isEmpty || year == null || file == null || mime == null) {
      _show('أدخل الاسم والسنة واختر صورة');
      return;
    }

    setState(() => _busy = true);
    try {
      final bytes = await file.readAsBytes();
      final presign = await _api.presignTrainerCertificateUpload(
        contentType: mime,
      );

      final putRes = await http.put(
        Uri.parse(presign.uploadUrl),
        headers: {'Content-Type': mime},
        body: bytes,
      );
      if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
        throw ApiException(putRes.statusCode, 'فشل رفع الصورة إلى التخزين');
      }

      await _api.createTrainerCertificate(
        name: name,
        year: year,
        imageUrl: presign.url,
        objectKey: presign.objectKey,
        description: desc.isEmpty ? null : desc,
      );

      setState(() {
        _nameController.clear();
        _yearController.clear();
        _descController.clear();
        _pickedImage = null;
        _pickedMime = null;
      });

      _show('تمت الإضافة');
      await _reload();
    } on ApiException catch (e) {
      _show(e.message);
    } catch (_) {
      _show('تعذر إضافة الشهادة/الوسام');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(String certificateId) async {
    if (_busy) return;

    setState(() => _busy = true);
    try {
      await _api.deleteTrainerCertificate(certificateId: certificateId);
      await _reload();
    } on ApiException catch (e) {
      _show(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الشهادات والأوسمة'),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF16162A),
                borderRadius: BorderRadius.circular(18),
                border:
                    Border.all(color: AppTheme.gold.withValues(alpha: 0.14)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      if (_busy)
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.primary,
                          ),
                        ),
                      const Spacer(),
                      const Icon(Icons.verified_outlined,
                          size: 18, color: AppTheme.gold),
                      const SizedBox(width: 8),
                      Text(
                        'إضافة شهادة / وسام (حد أقصى $_maxItems)',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.gold,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _nameController,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'اسم الشهادة / الوسام',
                      prefixIcon: Icon(Icons.badge_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'سنة الحصول',
                      prefixIcon: Icon(Icons.event_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _descController,
                    maxLines: 2,
                    textAlign: TextAlign.right,
                    decoration: const InputDecoration(
                      labelText: 'وصف قصير (اختياري)',
                      prefixIcon: Icon(Icons.notes_outlined, size: 18),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _busy
                              ? null
                              : () => _pickImage(ImageSource.gallery),
                          icon: const Icon(Icons.photo_library_outlined,
                              size: 16),
                          label: Text(_pickedImage == null
                              ? 'اختر صورة'
                              : 'تم اختيار صورة'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: const Icon(Icons.send_outlined, size: 16),
                          label: const Text('نشر'),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppTheme.gold,
                            foregroundColor: AppTheme.textOnGold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<Map<String, dynamic>>>(
              future: _itemsFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snapshot.hasError) {
                  return Card(
                    child: ListTile(
                      title: const Text('تعذر تحميل الشهادات'),
                      trailing: TextButton(
                          onPressed: _reload, child: const Text('إعادة')),
                    ),
                  );
                }

                final items = snapshot.data ?? const <Map<String, dynamic>>[];
                if (items.isEmpty) {
                  return const _EmptyBlock(
                      msg: 'لا توجد شهادات/أوسمة مضافة حالياً.');
                }

                return Column(
                  children: items.take(_maxItems).map((e) {
                    final id = (e['id'] ?? '').toString();
                    final name = (e['name'] ?? '').toString();
                    final year = e['year'];
                    final desc = (e['description'] ?? '').toString();

                    return Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: scheme.outline),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: _busy || id.isEmpty
                                ? null
                                : () async {
                                    final ok = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('حذف؟'),
                                        content: const Text(
                                            'سيتم حذف الشهادة/الوسام.'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(false),
                                            child: const Text('إلغاء'),
                                          ),
                                          FilledButton(
                                            onPressed: () =>
                                                Navigator.of(ctx).pop(true),
                                            child: const Text('حذف'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (ok == true) await _delete(id);
                                  },
                            icon: const Icon(Icons.delete_outline),
                            color: Colors.red,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  name,
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  year == null ? '' : 'سنة: ${year.toString()}',
                                  textAlign: TextAlign.end,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant),
                                ),
                                if (desc.isNotEmpty)
                                  Text(
                                    desc,
                                    textAlign: TextAlign.end,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                        color: scheme.onSurfaceVariant),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: AppTheme.gold.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.verified_outlined,
                                color: AppTheme.gold, size: 18),
                          ),
                        ],
                      ),
                    );
                  }).toList(growable: false),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyBlock extends StatelessWidget {
  const _EmptyBlock({required this.msg});
  final String msg;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outline),
      ),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style:
            theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}
