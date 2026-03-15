import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../plans/plans_api_service.dart';

/// A standalone page that lists the current user's trainer subscription
/// requests together with their live statuses (PENDING / APPROVED / REJECTED).
/// Opened from [UserHomePage] when the user taps the pending-notice banner.
class UserTrainerSubscriptionsPage extends StatefulWidget {
  const UserTrainerSubscriptionsPage({super.key, this.session});

  final AuthSession? session;

  @override
  State<UserTrainerSubscriptionsPage> createState() =>
      _UserTrainerSubscriptionsPageState();
}

class _UserTrainerSubscriptionsPageState
    extends State<UserTrainerSubscriptionsPage> {
  late final PlansApiService _api;
  late Future<List<MySubscription>> _future;
  final Set<String> _cancelling = {}; // trainerIds currently being cancelled

  @override
  void initState() {
    super.initState();
    _api = PlansApiService(
      role: widget.session?.role ?? AppRole.trainee,
      session: widget.session,
    );
    _future = _api.fetchMySubscriptions();
  }

  Future<void> _reload() async {
    setState(() => _future = _api.fetchMySubscriptions());
  }

  Future<void> _cancel(String trainerId) async {
    // Confirm
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16162A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('إلغاء طلب الاشتراك',
            style: TextStyle(
                color: AppTheme.textPrimary, fontWeight: FontWeight.w700)),
        content: const Text(
          'هل أنت متأكد من إلغاء هذا الطلب؟\nسيتم حذفه نهائياً.',
          style: TextStyle(color: AppTheme.textSecondary),
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع',
                style: TextStyle(color: AppTheme.textMuted)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('إلغاء الطلب'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _cancelling.add(trainerId));
    try {
      await _api.cancelTrainerSubscription(trainerId: trainerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إلغاء طلب الاشتراك ✓')),
        );
        _reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر الإلغاء: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _cancelling.remove(trainerId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppTheme.black,
      appBar: AppBar(
        backgroundColor: AppTheme.black,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_rounded,
              size: 18, color: AppTheme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'اشتراكاتي مع المدربين',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppTheme.gold,
                fontWeight: FontWeight.w800,
                fontSize: 17,
              ),
            ),
            Text(
              'حالة طلبات الاشتراك مع المدربين',
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                size: 20, color: AppTheme.textSecondary),
            onPressed: _reload,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        color: AppTheme.gold,
        child: FutureBuilder<List<MySubscription>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(
                child: CircularProgressIndicator(color: AppTheme.gold),
              );
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(32),
                children: [
                  const SizedBox(height: 40),
                  const Icon(Icons.error_outline,
                      size: 40, color: AppTheme.textMuted),
                  const SizedBox(height: 12),
                  Text(
                    'تعذر تحميل الاشتراكات',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: OutlinedButton.icon(
                      onPressed: _reload,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ),
                ],
              );
            }

            final subs = snapshot.data ?? [];

            if (subs.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
                children: [
                  _EmptySubscriptions(theme: theme),
                ],
              );
            }

            // Sort: PENDING first, then APPROVED, then REJECTED
            final sorted = [...subs]..sort((a, b) {
                const order = {'PENDING': 0, 'APPROVED': 1, 'REJECTED': 2};
                return (order[a.status] ?? 9).compareTo(order[b.status] ?? 9);
              });
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              itemCount: sorted.length + 1, // +1 for header
              itemBuilder: (context, index) {
                if (index == 0) return _buildHeader(context, sorted);
                final sub = sorted[index - 1];
                return _SubscriptionCard(
                  sub: sub,
                  theme: theme,
                  isCancelling: _cancelling.contains(sub.trainerId),
                  onCancel: sub.isPending ? () => _cancel(sub.trainerId) : null,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, List<MySubscription> subs) {
    final pending = subs.where((s) => s.isPending).length;
    final approved = subs.where((s) => s.isApproved).length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          if (pending > 0) ...[
            _StatPill(
              label: '$pending بانتظار الموافقة',
              color: const Color(0xFF92400E),
              bg: const Color(0xFFFEF3C7),
              icon: Icons.hourglass_top_outlined,
            ),
            const SizedBox(width: 8),
          ],
          if (approved > 0)
            _StatPill(
              label: '$approved مفعّل',
              color: AppTheme.success,
              bg: AppTheme.successContainer,
              icon: Icons.check_circle_outline_rounded,
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Subscription card
// ─────────────────────────────────────────────────────────────────────────────

class _SubscriptionCard extends StatelessWidget {
  const _SubscriptionCard({
    required this.sub,
    required this.theme,
    this.isCancelling = false,
    this.onCancel,
  });
  final MySubscription sub;
  final ThemeData theme;
  final bool isCancelling;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final isPending = sub.isPending;
    final isApproved = sub.isApproved;
    final isRejected = sub.status == 'REJECTED';

    // Status palette
    final Color statusColor;
    final Color statusBg;
    final String statusLabel;
    final IconData statusIcon;

    if (isPending) {
      statusColor = const Color(0xFF92400E);
      statusBg = const Color(0xFFFEF3C7);
      statusLabel = 'بانتظار موافقة المدرب';
      statusIcon = Icons.hourglass_top_outlined;
    } else if (isApproved) {
      statusColor = AppTheme.success;
      statusBg = AppTheme.successContainer;
      statusLabel = 'مفعّل';
      statusIcon = Icons.check_circle_outline_rounded;
    } else if (isRejected) {
      statusColor = Colors.red.shade700;
      statusBg = Colors.red.shade50;
      statusLabel = 'مرفوض';
      statusIcon = Icons.cancel_outlined;
    } else {
      statusColor = AppTheme.textSecondary;
      statusBg = const Color(0xFF1E1E32);
      statusLabel = sub.status;
      statusIcon = Icons.info_outline;
    }

    // Format date
    final dateStr = _formatDate(sub.requestedAt);

    // Trainer initials from ID (first 2 chars)
    final initial =
        sub.trainerId.isNotEmpty ? sub.trainerId[0].toUpperCase() : '؟';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isApproved
              ? AppTheme.gold.withValues(alpha: 0.30)
              : isPending
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.30)
                  : AppTheme.gold.withValues(alpha: 0.08),
        ),
        boxShadow: isApproved
            ? [
                BoxShadow(
                  color: AppTheme.gold.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Avatar / initial ──────────────────────
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: isApproved
                        ? const LinearGradient(
                            colors: [AppTheme.goldDeep, AppTheme.gold],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isApproved
                        ? null
                        : AppTheme.gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(
                        color: isApproved
                            ? AppTheme.textOnGold
                            : AppTheme.gold.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // ── Info ──────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'مدرب',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ID: ${sub.trainerId}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.textMuted,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (dateStr.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 11, color: AppTheme.textMuted),
                            const SizedBox(width: 4),
                            Text(
                              'أُرسل: $dateStr',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ],
                      // Plan info
                      if (sub.planName != null && sub.planName!.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(Icons.card_membership_outlined,
                                size: 11, color: AppTheme.gold),
                            const SizedBox(width: 4),
                            Text(
                              sub.planName!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                  color: AppTheme.gold,
                                  fontWeight: FontWeight.w600),
                            ),
                            if (sub.planPrice != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                '• ${sub.planPrice!.toStringAsFixed(0)} د.ع',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: AppTheme.textMuted),
                              ),
                            ],
                          ],
                        ),
                      ],
                      // Expiry
                      if (isApproved && sub.expiresAt != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            Icon(
                              Icons.event_available_outlined,
                              size: 11,
                              color: _isExpired(sub.expiresAt!)
                                  ? Colors.red.shade400
                                  : Colors.green.shade400,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _isExpired(sub.expiresAt!)
                                  ? 'انتهى: ${_formatDate(sub.expiresAt!)}'
                                  : 'ينتهي: ${_formatDate(sub.expiresAt!)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: _isExpired(sub.expiresAt!)
                                    ? Colors.red.shade400
                                    : Colors.green.shade400,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // ── Status badge ──────────────────────────
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(999),
                    border:
                        Border.all(color: statusColor.withValues(alpha: 0.30)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 5),
                      Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            // ── Cancel button (PENDING only) ──────────────
            if (onCancel != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: isCancelling
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppTheme.gold,
                          ),
                        ),
                      )
                    : OutlinedButton.icon(
                        onPressed: onCancel,
                        icon: const Icon(Icons.close_rounded, size: 15),
                        label: const Text('إلغاء الطلب'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red.shade400,
                          side: BorderSide(
                              color:
                                  Colors.red.shade700.withValues(alpha: 0.40)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.year}/${dt.month.toString().padLeft(2, '0')}/${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  bool _isExpired(String iso) {
    try {
      return DateTime.parse(iso).toLocal().isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat pill
// ─────────────────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.color,
    required this.bg,
    required this.icon,
  });
  final String label;
  final Color color;
  final Color bg;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptySubscriptions extends StatelessWidget {
  const _EmptySubscriptions({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: AppTheme.gold.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Icon(Icons.person_search_outlined,
              size: 34, color: AppTheme.gold),
        ),
        const SizedBox(height: 16),
        Text(
          'لا توجد اشتراكات مع مدربين',
          style: theme.textTheme.titleSmall?.copyWith(
            color: AppTheme.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'يمكنك الاشتراك مع مدرب من صفحة النادي',
          style: theme.textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
