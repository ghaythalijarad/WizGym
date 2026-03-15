import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';
import '../marketplace/user_marketplace_detail_page.dart';
import '../plans/plans_api_service.dart';
import 'user_trainer_subscriptions_page.dart';

class UserHomePage extends StatefulWidget {
  const UserHomePage({super.key, this.onGoToTab});

  /// Called with the tab index to switch to in the parent [RoleShell].
  /// Index 1 = النوادي, Index 2 = خططي
  final void Function(int tabIndex)? onGoToTab;

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  final AuthSessionStore _sessionStore = AuthSessionStore();
  late Future<_UserDashboardData> _dataFuture;
  AuthSession? _session; // cached after first load

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadDashboard();
  }

  Future<_UserDashboardData> _loadDashboard() async {
    final session = await _sessionStore.load();
    _session = session; // cache for navigation
    final plansApi = PlansApiService(
        role: session?.role ?? AppRole.trainee, session: session);
    final marketApi = MarketplaceApiService(
        role: session?.role ?? AppRole.trainee, session: session);

    final results = await Future.wait([
      plansApi.fetchMyPlans(),
      plansApi.fetchMySubscriptions(),
    ]);

    List<MyGymMembership> gymMemberships = [];
    try {
      gymMemberships = await marketApi.fetchMyGymMemberships();
    } catch (_) {}

    final plans = results[0] as List<PlanItem>;
    final subs = results[1] as List<MySubscription>;

    // ── Fetch products/announcements for active gyms ──────────
    final activeGyms =
        gymMemberships.where((m) => m.isActive && !m.isExpired).toList();

    final gymFeedItems = <_GymFeedItem>[];
    await Future.wait(activeGyms.map((m) async {
      try {
        final detail = await marketApi.fetchGymDetail(m.gymId);
        for (final product in detail.products) {
          gymFeedItems.add(_GymFeedItem(gymName: m.gymName, product: product));
        }
      } catch (_) {}
    }));

    return _UserDashboardData(
      totalPlans: plans.length,
      trainerPlans: plans.where((p) => p.isFromTrainer).length,
      activeTrainerSubscriptions: subs.where((s) => s.isApproved).length,
      pendingTrainerSubscriptions: subs.where((s) => s.isPending).length,
      activeGymMemberships:
          gymMemberships.where((m) => m.isActive && !m.isExpired).length,
      pendingGymMemberships: gymMemberships.where((m) => m.isPending).length,
      gymMemberships: gymMemberships,
      gymFeedItems: gymFeedItems,
      displayName: session?.displayName ?? '',
    );
  }

  Future<void> _refresh() async {
    setState(() => _dataFuture = _loadDashboard());
  }

  String _greetingSubtitle(_UserDashboardData data) {
    if (data.activeGymMemberships > 0) {
      return 'لديك ${data.activeGymMemberships} اشتراك نشط — استمر في التقدم!';
    }
    if (data.pendingGymMemberships > 0) {
      return 'طلباتك قيد المراجعة، سنبلغك فور الموافقة.';
    }
    return 'انضم إلى نادٍ وابدأ رحلتك اليوم.';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_UserDashboardData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 40),
                Icon(Icons.error_outline,
                    size: 40, color: scheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'تعذر تحميل البيانات',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                Center(
                  child: OutlinedButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('إعادة المحاولة'),
                  ),
                ),
              ],
            );
          }

          final data = snapshot.data!;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              // ── Greeting ──────────────────────────────────────
              if (data.displayName.isNotEmpty) ...[
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: 'أهلاً ',
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w400,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      TextSpan(
                        text: data.displayName,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppTheme.gold,
                        ),
                      ),
                      TextSpan(
                        text: ' 👋',
                        style: theme.textTheme.headlineSmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _greetingSubtitle(data),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
              ],

              // ── Stats ─────────────────────────────────────────
              _SummaryRow(data: data, onGoToTab: widget.onGoToTab),
              const SizedBox(height: 20),

              // ── Pending notice ────────────────────────────────
              if (data.pendingGymMemberships > 0 ||
                  data.pendingTrainerSubscriptions > 0) ...[
                _PendingNotice(
                  gymCount: data.pendingGymMemberships,
                  trainerCount: data.pendingTrainerSubscriptions,
                  // Gym pending → marketplace tab (owner approves there).
                  // Trainer pending → dedicated trainer-subscriptions page.
                  // Both pending → push trainer page first (user can swipe
                  //   back and then go to marketplace for the gym part).
                  onTapGym: data.pendingGymMemberships > 0
                      ? () => widget.onGoToTab?.call(1)
                      : null,
                  onTapTrainer: data.pendingTrainerSubscriptions > 0
                      ? () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => UserTrainerSubscriptionsPage(
                                  session: _session),
                            ),
                          )
                      : null,
                ),
                const SizedBox(height: 20),
              ],

              // ── Gym memberships ───────────────────────────────
              if (data.gymMemberships.isNotEmpty) ...[
                _SectionHeader(
                  title: 'اشتراكات النوادي',
                  actionLabel: 'استعراض النوادي',
                  onAction: () => widget.onGoToTab?.call(1),
                ),
                const SizedBox(height: 10),
                ...data.gymMemberships.map((m) =>
                    _GymMembershipTile(membership: m, session: _session)),
              ] else ...[
                _EmptyState(
                  icon: Icons.fitness_center_outlined,
                  message: 'لم تنضم إلى أي نادٍ بعد',
                  actionLabel: 'تصفّح النوادي',
                  onAction: () => widget.onGoToTab?.call(1),
                ),
              ],

              // ── Gym products / announcements feed ─────────────
              if (data.gymFeedItems.isNotEmpty) ...[
                const SizedBox(height: 24),
                const _SectionHeader(
                  title: 'إعلانات وعروض النوادي',
                ),
                const SizedBox(height: 10),
                ...data.gymFeedItems.map((item) => _GymProductCard(item: item)),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Summary row
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.data, this.onGoToTab});
  final _UserDashboardData data;
  final void Function(int)? onGoToTab;

  @override
  Widget build(BuildContext context) {
    final totalActive =
        data.activeTrainerSubscriptions + data.activeGymMemberships;

    return Row(
      children: [
        _StatChip(
          label: 'اشتراكات نشطة',
          value: totalActive,
          onTap: () => onGoToTab?.call(1),
        ),
        const SizedBox(width: 8),
        _StatChip(
          label: 'خططي',
          value: data.totalPlans,
          onTap: () => onGoToTab?.call(2),
        ),
        if (data.trainerPlans > 0) ...[
          const SizedBox(width: 8),
          _StatChip(
            label: 'من مدرب',
            value: data.trainerPlans,
            onTap: () => onGoToTab?.call(2),
          ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value, this.onTap});
  final String label;
  final int value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final hasValue = value > 0;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
          decoration: BoxDecoration(
            color: hasValue
                ? AppTheme.gold.withValues(alpha: 0.07)
                : scheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: hasValue
                  ? AppTheme.gold.withValues(alpha: 0.35)
                  : scheme.outline,
              width: hasValue ? 1.5 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 28,
                  color: hasValue ? AppTheme.gold : AppTheme.textMuted,
                  height: 1,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  letterSpacing: 0.2,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Pending notice
// ─────────────────────────────────────────────────────────────────────────────

class _PendingNotice extends StatelessWidget {
  const _PendingNotice({
    required this.gymCount,
    required this.trainerCount,
    this.onTapGym,
    this.onTapTrainer,
  });
  final int gymCount;
  final int trainerCount;
  final VoidCallback? onTapGym;
  final VoidCallback? onTapTrainer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Build one row per pending entity type, each with its own tap target.
    final rows = <Widget>[];

    if (gymCount > 0) {
      rows.add(_PendingRow(
        label:
            '${gymCount == 1 ? 'نادٍ' : '$gymCount نوادٍ'} بانتظار موافقة المالك',
        onTap: onTapGym,
        theme: theme,
      ));
    }
    if (trainerCount > 0) {
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 6));
      rows.add(_PendingRow(
        label:
            '${trainerCount == 1 ? 'مدرب' : '$trainerCount مدربين'} بانتظار موافقة المدرب',
        onTap: onTapTrainer,
        theme: theme,
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: Column(children: rows),
    );
  }
}

/// A single tappable row inside [_PendingNotice].
class _PendingRow extends StatelessWidget {
  const _PendingRow({required this.label, required this.theme, this.onTap});
  final String label;
  final VoidCallback? onTap;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final row = Row(
      children: [
        const Icon(Icons.hourglass_top_outlined,
            size: 16, color: Color(0xFF92400E)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF92400E),
              fontWeight: FontWeight.w600,
            ),
            textDirection: TextDirection.rtl,
          ),
        ),
        if (onTap != null)
          const Icon(Icons.chevron_left, size: 16, color: Color(0xFF92400E)),
      ],
    );

    if (onTap == null) return row;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    this.actionLabel,
    this.onAction,
  });
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: [
        if (actionLabel != null && onAction != null)
          GestureDetector(
            onTap: onAction,
            child: Text(
              actionLabel!,
              style:
                  theme.textTheme.labelMedium?.copyWith(color: scheme.primary),
            ),
          ),
        const Spacer(),
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
            color: scheme.outline.withValues(alpha: 0.6),
            style: BorderStyle.solid),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon,
                size: 22, color: AppTheme.gold.withValues(alpha: 0.6)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: AppTheme.gold.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null && onAction != null)
            const Icon(Icons.arrow_back_ios_rounded,
                size: 14, color: AppTheme.textMuted),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gym membership tile
// ─────────────────────────────────────────────────────────────────────────────

class _GymMembershipTile extends StatelessWidget {
  const _GymMembershipTile({required this.membership, this.session});
  final MyGymMembership membership;
  final AuthSession? session;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = membership;

    final String statusLabel;
    final Color statusColor;
    final Color statusBg;
    if (m.isPending) {
      statusLabel = 'بانتظار الموافقة';
      statusColor = const Color(0xFF92400E); // dark amber — 7.2:1 on amber-50 ✓
      statusBg = const Color(0xFFFEF3C7); // amber-50
    } else if (m.isActive && m.isExpired) {
      statusLabel = 'منتهي';
      statusColor = scheme.error;
      statusBg = scheme.errorContainer;
    } else if (m.isActive) {
      statusLabel = 'فعّال';
      statusColor = AppTheme.success; // #15803D — 7.0:1 on successContainer ✓
      statusBg = AppTheme.successContainer;
    } else {
      statusLabel = m.status;
      statusColor = AppTheme.textSecondary;
      statusBg = scheme.surfaceContainerHighest;
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => UserMarketplaceDetailPage(
              gymId: m.gymId,
              gymName: m.gymName,
              session: session,
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: m.isActive && !m.isExpired
                ? AppTheme.gold.withValues(alpha: 0.25)
                : scheme.outline,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left: icon ──────────────────────────────────
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: m.isActive && !m.isExpired
                      ? AppTheme.gold.withValues(alpha: 0.12)
                      : scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  Icons.fitness_center_outlined,
                  size: 20,
                  color: m.isActive && !m.isExpired
                      ? AppTheme.gold
                      : AppTheme.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              // ── Right: info ─────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            m.gymName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: statusBg,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            statusLabel,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: statusColor,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (m.gymCity.isNotEmpty) m.gymCity,
                        if (m.selectedPlanTitle != null &&
                            m.selectedPlanTitle!.isNotEmpty)
                          m.selectedPlanTitle!,
                      ].join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    if (m.subscriptionExpiresAt != null && m.isActive) ...[
                      const SizedBox(height: 3),
                      Text(
                        '${m.isExpired ? 'انتهى' : 'ينتهي'}: ${_formatDate(m.subscriptionExpiresAt!)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color:
                              m.isExpired ? scheme.error : AppTheme.textMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data model
// ─────────────────────────────────────────────────────────────────────────────

class _UserDashboardData {
  const _UserDashboardData({
    required this.totalPlans,
    required this.trainerPlans,
    required this.activeTrainerSubscriptions,
    required this.pendingTrainerSubscriptions,
    required this.activeGymMemberships,
    required this.pendingGymMemberships,
    required this.gymMemberships,
    required this.gymFeedItems,
    required this.displayName,
  });

  final int totalPlans;
  final int trainerPlans;
  final int activeTrainerSubscriptions;
  final int pendingTrainerSubscriptions;
  final int activeGymMemberships;
  final int pendingGymMemberships;
  final List<MyGymMembership> gymMemberships;
  final List<_GymFeedItem> gymFeedItems;
  final String displayName;
}

// ─────────────────────────────────────────────────────────────────────────────
// Gym feed item — one product/announcement with its gym name
// ─────────────────────────────────────────────────────────────────────────────

class _GymFeedItem {
  const _GymFeedItem({required this.gymName, required this.product});
  final String gymName;
  final GymProductItem product;
}

// ─────────────────────────────────────────────────────────────────────────────
// Gym product / announcement card
// ─────────────────────────────────────────────────────────────────────────────

class _GymProductCard extends StatelessWidget {
  const _GymProductCard({required this.item});
  final _GymFeedItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = item.product;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.22)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.gold.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Icon ────────────────────────────────────────────
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.storefront_outlined,
                  size: 22, color: AppTheme.gold),
            ),
            const SizedBox(width: 14),
            // ── Content ─────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Gym name badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      item.gymName,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    p.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  if (p.description != null && p.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      p.description!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppTheme.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // ── Price badge ──────────────────────────────────────
            if (p.price != null) ...[
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${p.price} د.ع',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.textOnGold,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
