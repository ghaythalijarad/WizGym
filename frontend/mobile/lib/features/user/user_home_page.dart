import 'package:flutter/material.dart';

import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/metric_card.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';
import '../plans/plans_api_service.dart';
import '../plans/user_plans_page.dart';

class UserHomePage extends StatefulWidget {
  const UserHomePage({super.key});

  @override
  State<UserHomePage> createState() => _UserHomePageState();
}

class _UserHomePageState extends State<UserHomePage> {
  final AuthSessionStore _sessionStore = AuthSessionStore();
  late Future<_UserDashboardData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadDashboard();
  }

  Future<_UserDashboardData> _loadDashboard() async {
    final session = await _sessionStore.load();
    final plansApi = PlansApiService(
        role: session?.role ?? AppRole.trainee, session: session);
    final marketApi = MarketplaceApiService(
        role: session?.role ?? AppRole.trainee, session: session);

    final results = await Future.wait([
      plansApi.fetchMyPlans(),
      plansApi.fetchMySubscriptions(),
    ]);

    // Gym memberships call is separate so a failure doesn't break the page
    List<MyGymMembership> gymMemberships = [];
    try {
      gymMemberships = await marketApi.fetchMyGymMemberships();
    } catch (_) {
      // Endpoint may not be deployed yet — silently degrade
    }

    final plans = results[0] as List<PlanItem>;
    final subs = results[1] as List<MySubscription>;

    // Trainer subscriptions
    final activeTrainerSubs = subs.where((s) => s.isApproved).length;
    final pendingTrainerSubs = subs.where((s) => s.isPending).length;

    // Gym memberships
    final activeGymSubs =
        gymMemberships.where((m) => m.isActive && !m.isExpired).length;
    final pendingGymSubs = gymMemberships.where((m) => m.isPending).length;

    return _UserDashboardData(
      totalPlans: plans.length,
      trainerPlans: plans.where((p) => p.isFromTrainer).length,
      activeTrainerSubscriptions: activeTrainerSubs,
      pendingTrainerSubscriptions: pendingTrainerSubs,
      activeGymMemberships: activeGymSubs,
      pendingGymMemberships: pendingGymSubs,
      gymMemberships: gymMemberships,
      displayName: session?.displayName ?? '',
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = _loadDashboard();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
                const Icon(Icons.error_outline, size: 42, color: Colors.red),
                const SizedBox(height: 10),
                Text('تعذر تحميل البيانات',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge),
                const SizedBox(height: 12),
                Center(
                  child: FilledButton.icon(
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('إعادة المحاولة'),
                  ),
                ),
              ],
            );
          }

          final data = snapshot.data!;
          final totalActive =
              data.activeTrainerSubscriptions + data.activeGymMemberships;
          final totalPending =
              data.pendingTrainerSubscriptions + data.pendingGymMemberships;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (data.displayName.isNotEmpty) ...[
                Text(
                  'مرحباً، ${data.displayName} 👋',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: AppTheme.cardLime),
                ),
                const SizedBox(height: 16),
              ],
              MetricCard(
                title: 'خططي التدريبية',
                value: '${data.totalPlans}',
                icon: Icons.fitness_center_outlined,
                onTap: () async {
                  final session = await _sessionStore.load();
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserPlansPage(session: session),
                    ),
                  );
                },
              ),
              MetricCard(
                title: 'خطط من المدربين',
                value: '${data.trainerPlans}',
                icon: Icons.person_outline,
                onTap: () async {
                  final session = await _sessionStore.load();
                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => UserPlansPage(session: session),
                    ),
                  );
                },
              ),
              MetricCard(
                title: 'اشتراكات نشطة',
                value: '$totalActive',
                icon: Icons.check_circle_outline,
                onTap: totalActive > 0
                    ? () {
                        // Navigate to subscriptions page or show details
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('عرض الاشتراكات النشطة')),
                        );
                      }
                    : null,
              ),
              if (totalPending > 0)
                MetricCard(
                  title: 'اشتراكات معلقة',
                  value: '$totalPending',
                  icon: Icons.hourglass_top_outlined,
                  onTap: () {
                    // Navigate to pending subscriptions
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('عرض الاشتراكات المعلقة')),
                    );
                  },
                ),

              // ── Gym memberships detail section ──────────────
              if (data.gymMemberships.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text(
                  'اشتراكات النوادي',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                ...data.gymMemberships
                    .map((m) => _GymMembershipTile(membership: m)),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _GymMembershipTile extends StatelessWidget {
  const _GymMembershipTile({required this.membership});
  final MyGymMembership membership;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final m = membership;

    // Status label & color
    String statusLabel;
    Color statusColor;
    if (m.isPending) {
      statusLabel = 'بانتظار الموافقة';
      statusColor = Colors.orange;
    } else if (m.isActive && !m.isExpired) {
      statusLabel = 'فعّال';
      statusColor = Colors.green;
    } else if (m.isActive && m.isExpired) {
      statusLabel = 'منتهي';
      statusColor = Colors.red;
    } else {
      statusLabel = m.status;
      statusColor = Colors.grey;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Gym name + status chip
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    statusLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    m.gymName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 6),
                Icon(Icons.fitness_center, size: 18, color: scheme.primary),
              ],
            ),

            if (m.gymCity.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                m.gymCity,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],

            // Plan info
            if (m.selectedPlanTitle != null &&
                m.selectedPlanTitle!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    m.selectedPlanTitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.card_membership,
                      size: 14, color: scheme.onSurfaceVariant),
                ],
              ),
            ],

            // Expiry date
            if (m.subscriptionExpiresAt != null) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    _formatDate(m.subscriptionExpiresAt!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: m.isExpired ? Colors.red : Colors.green,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'ينتهي:',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ],
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

class _UserDashboardData {
  const _UserDashboardData({
    required this.totalPlans,
    required this.trainerPlans,
    required this.activeTrainerSubscriptions,
    required this.pendingTrainerSubscriptions,
    required this.activeGymMemberships,
    required this.pendingGymMemberships,
    required this.gymMemberships,
    required this.displayName,
  });

  final int totalPlans;
  final int trainerPlans;
  final int activeTrainerSubscriptions;
  final int pendingTrainerSubscriptions;
  final int activeGymMemberships;
  final int pendingGymMemberships;
  final List<MyGymMembership> gymMemberships;
  final String displayName;
}
