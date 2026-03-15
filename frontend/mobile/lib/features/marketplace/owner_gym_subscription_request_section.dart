import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../../core/theme/app_theme.dart';
import 'marketplace_api_service.dart';

class OwnerGymSubscriptionRequestSection extends StatefulWidget {
  const OwnerGymSubscriptionRequestSection({
    super.key,
    required this.gymId,
    required this.api,
  });

  final String gymId;
  final MarketplaceApiService api;

  @override
  State<OwnerGymSubscriptionRequestSection> createState() =>
      _OwnerGymSubscriptionRequestSectionState();
}

class _OwnerGymSubscriptionRequestSectionState
    extends State<OwnerGymSubscriptionRequestSection> {
  static const String _transferPhone = '07831367435';

  final ImagePicker _picker = ImagePicker();

  bool _busy = false;
  late Future<List<PlatformSubscriptionPlan>> _plansFuture;
  late Future<List<GymSubscriptionRequestItem>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _plansFuture = widget.api.fetchPlatformSubscriptionPlans();
    _requestsFuture = widget.api.fetchMyGymSubscriptionRequests(widget.gymId);
  }

  Future<void> _reload() async {
    setState(() {
      _plansFuture = widget.api.fetchPlatformSubscriptionPlans();
      _requestsFuture = widget.api.fetchMyGymSubscriptionRequests(widget.gymId);
    });
  }

  String _guessMime(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic') || lower.endsWith('.heif')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _startRequestFlow(PlatformSubscriptionPlan plan) async {
    if (_busy) return;

    // Step 1: confirm plan
    final confirmedPlan = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('تأكيد الخطة'),
          content: Text(
            'هل تريد طلب تفعيل اشتراك الاستوديو بهذه الخطة؟\n\n'
            '${plan.labelAr} • ${plan.price} ${plan.currency}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('متابعة'),
            ),
          ],
        );
      },
    );
    if (confirmedPlan != true || !mounted) return;

    // Step 2: show payment instructions and require screenshot
    final proceed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text('الدفع عبر زين كاش'),
          content: const Text(
            'يرجى تحويل مبلغ الاشتراك عبر زين كاش وإرسال سكرينشوت التحويل.\n\n'
            'رقم الاستلام: 07831367435',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('رفع السكرينشوت'),
            ),
          ],
        );
      },
    );
    if (proceed != true || !mounted) return;

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
      maxWidth: 2200,
    );
    if (picked == null) return;

    setState(() => _busy = true);
    try {
      // iOS: XFile path can be temporary/unavailable; read bytes via XFile API.
      final bytes = await picked.readAsBytes();

      final mime = _guessMime(picked.path);
      final presign = await widget.api.presignSubscriptionProofUpload(
        widget.gymId,
        contentType: mime,
      );

      // Upload to S3 using the pre-signed URL
      final putRes = await http.put(
        Uri.parse(presign.uploadUrl),
        headers: {
          'Content-Type': mime,
        },
        body: bytes,
      );

      if (putRes.statusCode < 200 || putRes.statusCode >= 300) {
        throw ApiException(putRes.statusCode, 'فشل رفع سكرينشوت الدفع');
      }

      await widget.api.createGymSubscriptionRequest(
        widget.gymId,
        planId: plan.planId,
        screenshotUrl: presign.url,
        screenshotObjectKey: presign.objectKey,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب التفعيل بنجاح')),
      );
      await _reload();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      // Surface common iOS/local file errors with a friendlier hint.
      final msg = e.toString().contains('No such file') ||
              e.toString().contains('path')
          ? 'تعذر الوصول للصورة المختارة. جرّب اختيار صورة أخرى أو التقط صورة جديدة.'
          : 'حدث خطأ أثناء إرسال الطلب';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Color _statusColor(BuildContext context, String status) {
    final s = status.toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    if (s == 'APPROVED') return AppTheme.success;
    if (s == 'REJECTED') return scheme.error;
    return scheme.primary;
  }

  String _statusLabel(String status) {
    switch (status.toUpperCase()) {
      case 'APPROVED':
        return 'تمت الموافقة';
      case 'REJECTED':
        return 'مرفوض';
      default:
        return 'قيد المراجعة';
    }
  }

  DateTime? _tryParseIso(String value) {
    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {
      return null;
    }
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '-';
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  String _fmtRequestDate(String createdAt) {
    final dt = _tryParseIso(createdAt);
    // Fallback: if parsing fails, show a shortened string without time.
    return dt != null ? _fmtDate(dt) : createdAt.split('T').first;
  }

  DateTime _addMonths(DateTime date, int months) {
    // Keep same day where possible; if day doesn't exist, clamp to month end.
    final targetMonth = date.month + months;
    final year = date.year + ((targetMonth - 1) ~/ 12);
    final month = ((targetMonth - 1) % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(
      year,
      month,
      day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
      date.microsecond,
    );
  }

  DateTime _endExclusive(DateTime startInclusive, int durationMonths) {
    // End date shown to user: last day of subscription.
    // We compute an exclusive end at start+months then subtract one day for display.
    final startDate =
        DateTime(startInclusive.year, startInclusive.month, startInclusive.day);
    final nextPeriodStart = _addMonths(startDate, durationMonths);
    return nextPeriodStart.subtract(const Duration(days: 1));
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'تفعيل اشتراك الاستوديو',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'اختر خطة ثم اتبع خطوات الدفع عبر زين كاش. سيتم مراجعة الطلب من الإدارة ثم تفعيل الاشتراك.',
            ),
            const SizedBox(height: 10),

            // Plans
            FutureBuilder<List<PlatformSubscriptionPlan>>(
              future: _plansFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 14),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return ListTile(
                    title: const Text('تعذر تحميل خطط الاشتراك'),
                    trailing: TextButton(
                      onPressed: _busy ? null : _reload,
                      child: const Text('إعادة'),
                    ),
                  );
                }

                final plans = snap.data ?? const <PlatformSubscriptionPlan>[];
                if (plans.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('لا توجد خطط حالياً — تواصل مع الإدارة.'),
                  );
                }

                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: plans.map((p) {
                    return FilledButton.tonal(
                      onPressed: _busy ? null : () => _startRequestFlow(p),
                      child: Text('${p.labelAr} • ${p.price} ${p.currency}'),
                    );
                  }).toList(growable: false),
                );
              },
            ),

            const SizedBox(height: 14),
            Divider(color: Theme.of(context).dividerColor.withAlpha(128)),
            const SizedBox(height: 10),

            // Existing requests
            Row(
              children: [
                Expanded(
                  child: Text(
                    'طلباتك السابقة',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : _reload,
                  child: const Text('تحديث'),
                ),
              ],
            ),
            FutureBuilder<List<GymSubscriptionRequestItem>>(
              future: _requestsFuture,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('تعذر تحميل الطلبات السابقة.'),
                  );
                }

                final reqs = snap.data ?? const <GymSubscriptionRequestItem>[];
                if (reqs.isEmpty) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('لا توجد طلبات حتى الآن.'),
                  );
                }

                // Compute subscription start/end for each approved request, stacked to avoid overlap.
                final approved = reqs
                    .where((r) => r.status.toUpperCase() == 'APPROVED')
                    .toList(growable: false);
                approved.sort((a, b) => a.createdAt.compareTo(b.createdAt));

                final Map<String, ({DateTime? start, DateTime? end})> schedule =
                    {};
                DateTime? lastApprovedEnd;

                for (final r in approved) {
                  final created = _tryParseIso(r.createdAt);
                  // If there's a previous approved subscription, start after it ends.
                  // Otherwise we treat approval as effective from request date (createdAt).
                  final start = (lastApprovedEnd != null)
                      ? DateTime(
                          lastApprovedEnd.year,
                          lastApprovedEnd.month,
                          lastApprovedEnd.day,
                        ).add(const Duration(days: 1))
                      : (created != null
                          ? DateTime(created.year, created.month, created.day)
                          : null);

                  final end = (start == null)
                      ? null
                      : _endExclusive(start, r.durationMonths);

                  schedule[r.requestId] = (start: start, end: end);
                  if (end != null) lastApprovedEnd = end;
                }

                return Column(
                  children: reqs.map((r) {
                    final sl = schedule[r.requestId];
                    final extraDates = (r.status.toUpperCase() == 'APPROVED' &&
                            sl != null)
                        ? '\nبداية الاشتراك: ${_fmtDate(sl.start)}\nنهاية الاشتراك: ${_fmtDate(sl.end)}'
                        : '';

                    final statusClr = _statusColor(context, r.status);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Theme.of(context).colorScheme.outline),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            // Status badge
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: statusClr.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    _statusLabel(r.status),
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: statusClr,
                                          fontWeight: FontWeight.w700,
                                        ),
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  '${r.durationMonths} شهر • ${r.price} ${r.currency}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'التحويل إلى: ${r.transferToPhone.isEmpty ? _transferPhone : r.transferToPhone}',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.end,
                            ),
                            Text(
                              'تاريخ الطلب: ${_fmtRequestDate(r.createdAt)}$extraDates',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.end,
                            ),
                          ],
                        ),
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
