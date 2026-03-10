import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../shared/widgets/metric_card.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';
import 'owner_create_gym_page.dart';

class OwnerHomePage extends StatefulWidget {
  const OwnerHomePage({super.key, this.session});

  final AuthSession? session;

  @override
  State<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends State<OwnerHomePage> {
  late final MarketplaceApiService _api;
  late Future<List<GymSummary>> _gymsFuture;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
    _gymsFuture = _api.fetchOwnerGyms();
  }

  void _reload() {
    setState(() => _gymsFuture = _api.fetchOwnerGyms());
  }

  Future<void> _openCreateGym() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OwnerCreateGymPage(session: widget.session),
      ),
    );
    if (result == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _gymsFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          const MetricCard(
              title: 'الاشتراكات النشطة',
              value: '-',
              icon: Icons.groups_outlined),
          const MetricCard(
              title: 'إيراد اليوم', value: '-', icon: Icons.payments_outlined),
          const MetricCard(
              title: 'نسبة الحضور',
              value: '-',
              icon: Icons.query_stats_outlined),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text('نواديي',
                    style: Theme.of(context).textTheme.titleLarge),
              ),
              FilledButton.icon(
                onPressed: _openCreateGym,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إنشاء نادي'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FutureBuilder<List<GymSummary>>(
            future: _gymsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final gyms = snap.data ?? [];
              if (gyms.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child:
                        Text('لا توجد نوادي مملوكة لك حالياً. أنشئ نادي جديد!'),
                  ),
                );
              }
              return Column(
                children: gyms.map((g) => _GymCard(gym: g)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GymCard extends StatelessWidget {
  const _GymCard({required this.gym});
  final GymSummary gym;

  @override
  Widget build(BuildContext context) {
    final isPending = gym.status == 'PENDING_APPROVAL';
    final isRejected = gym.status == 'REJECTED';
    final statusColor = isPending
        ? Colors.orange
        : isRejected
            ? Colors.red
            : Colors.green;
    final statusLabel = isPending
        ? 'بانتظار الاعتماد'
        : isRejected
            ? 'مرفوض'
            : 'فعّال';

    return Card(
      child: ListTile(
        leading: const Icon(Icons.fitness_center),
        title: Text(gym.name),
        subtitle: Text('${gym.city} — أعضاء: ${gym.membersCount}'),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(statusLabel,
              style: TextStyle(
                  color: statusColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12)),
        ),
      ),
    );
  }
}
