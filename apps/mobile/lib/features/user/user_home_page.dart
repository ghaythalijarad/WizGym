import 'package:flutter/material.dart';

import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/metric_card.dart';
import '../plans/plans_api_service.dart';

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
    final api = PlansApiService(
        role: session?.role ?? AppRole.trainee, session: session);

    final results = await Future.wait([
      api.fetchMyPlans(),
      api.fetchMySubscriptions(),
    ]);

    final plans = results[0] as List<PlanItem>;
    final subs = results[1] as List<MySubscription>;

    return _UserDashboardData(
      totalPlans: plans.length,
      trainerPlans: plans.where((p) => p.isFromTrainer).length,
      activeSubscriptions: subs.where((s) => s.isApproved).length,
      pendingSubscriptions: subs.where((s) => s.isPending).length,
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
              ),
              MetricCard(
                title: 'خطط من المدربين',
                value: '${data.trainerPlans}',
                icon: Icons.person_outline,
              ),
              MetricCard(
                title: 'اشتراكات نشطة',
                value: '${data.activeSubscriptions}',
                icon: Icons.check_circle_outline,
              ),
              if (data.pendingSubscriptions > 0)
                MetricCard(
                  title: 'اشتراكات معلقة',
                  value: '${data.pendingSubscriptions}',
                  icon: Icons.hourglass_top_outlined,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _UserDashboardData {
  const _UserDashboardData({
    required this.totalPlans,
    required this.trainerPlans,
    required this.activeSubscriptions,
    required this.pendingSubscriptions,
    required this.displayName,
  });

  final int totalPlans;
  final int trainerPlans;
  final int activeSubscriptions;
  final int pendingSubscriptions;
  final String displayName;
}
