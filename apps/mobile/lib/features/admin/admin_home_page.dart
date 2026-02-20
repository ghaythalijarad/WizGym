import 'package:flutter/material.dart';

import '../../shared/widgets/metric_card.dart';
import 'admin_api_service.dart';
import 'admin_models.dart';

class AdminHomePage extends StatefulWidget {
  const AdminHomePage({super.key});

  @override
  State<AdminHomePage> createState() => _AdminHomePageState();
}

class _AdminHomePageState extends State<AdminHomePage> {
  final AdminApiService _api = AdminApiService();
  late Future<AdminDashboardSummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _api.fetchDashboard();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<AdminDashboardSummary>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: 'تعذر تحميل لوحة المدير',
              onRetry: _reload,
            );
          }

          final summary = snapshot.data;
          if (summary == null) {
            return _ErrorState(
              message: 'البيانات غير متاحة حالياً',
              onRetry: _reload,
            );
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              MetricCard(
                title: 'طلبات نوادي معلقة',
                value: '${summary.pendingGymApprovals}',
                icon: Icons.pending_actions_outlined,
              ),
              MetricCard(
                title: 'النوادي المعتمدة',
                value: '${summary.approvedGyms}',
                icon: Icons.verified_outlined,
              ),
              MetricCard(
                title: 'الاشتراكات النشطة',
                value: '${summary.activeSubscriptions}',
                icon: Icons.card_membership_outlined,
              ),
              MetricCard(
                title: 'الاشتراكات الموقوفة',
                value: '${summary.pausedSubscriptions}',
                icon: Icons.pause_circle_outline,
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _summaryFuture = _api.fetchDashboard();
    });

    await _summaryFuture;
  }

  void _reload() {
    setState(() {
      _summaryFuture = _api.fetchDashboard();
    });
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.error_outline, size: 42, color: Colors.red.shade700),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
