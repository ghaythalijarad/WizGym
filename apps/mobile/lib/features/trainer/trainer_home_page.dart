import 'package:flutter/material.dart';

import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/metric_card.dart';
import '../plans/plans_api_service.dart';

class TrainerHomePage extends StatefulWidget {
  const TrainerHomePage({super.key});

  @override
  State<TrainerHomePage> createState() => _TrainerHomePageState();
}

class _TrainerHomePageState extends State<TrainerHomePage> {
  final AuthSessionStore _sessionStore = AuthSessionStore();
  late Future<_TrainerDashboardData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _dataFuture = _loadDashboard();
  }

  Future<_TrainerDashboardData> _loadDashboard() async {
    final session = await _sessionStore.load();
    final api = PlansApiService(
        role: session?.role ?? AppRole.trainer, session: session);

    final results = await Future.wait([
      api.fetchTrainerClients(),
      api.fetchSubscriptionRequests(),
      api.fetchSubscriptionRequests(status: 'PENDING'),
    ]);

    final clients = results[0] as List<TrainerClientSummary>;
    final allRequests = results[1] as List<SubscriptionRequest>;
    final pendingRequests = results[2] as List<SubscriptionRequest>;

    return _TrainerDashboardData(
      activeClients: clients.length,
      totalRequests: allRequests.length,
      pendingRequests: pendingRequests.length,
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
      child: FutureBuilder<_TrainerDashboardData>(
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
                title: 'عملاء نشطون',
                value: '${data.activeClients}',
                icon: Icons.people_alt_outlined,
              ),
              MetricCard(
                title: 'إجمالي الطلبات',
                value: '${data.totalRequests}',
                icon: Icons.list_alt_outlined,
              ),
              if (data.pendingRequests > 0)
                MetricCard(
                  title: 'طلبات بانتظار الرد',
                  value: '${data.pendingRequests}',
                  icon: Icons.hourglass_top_outlined,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _TrainerDashboardData {
  const _TrainerDashboardData({
    required this.activeClients,
    required this.totalRequests,
    required this.pendingRequests,
    required this.displayName,
  });

  final int activeClients;
  final int totalRequests;
  final int pendingRequests;
  final String displayName;
}
