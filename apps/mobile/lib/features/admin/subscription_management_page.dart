import 'package:flutter/material.dart';

import 'admin_api_service.dart';
import 'admin_models.dart';

class SubscriptionManagementPage extends StatefulWidget {
  const SubscriptionManagementPage({super.key});

  @override
  State<SubscriptionManagementPage> createState() => _SubscriptionManagementPageState();
}

class _SubscriptionManagementPageState extends State<SubscriptionManagementPage> {
  final AdminApiService _api = AdminApiService();
  late Future<List<GymSubscription>> _subscriptionsFuture;

  @override
  void initState() {
    super.initState();
    _subscriptionsFuture = _api.fetchSubscriptions();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<GymSubscription>>(
        future: _subscriptionsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(onRetry: _reload);
          }

          final subscriptions = snapshot.data ?? const <GymSubscription>[];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('إدارة الاشتراكات', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'غيّر حالة اشتراك أي نادي بين نشط أو موقوف أو ملغي.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ...subscriptions.map((item) => _buildSubscriptionCard(context, item)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSubscriptionCard(BuildContext context, GymSubscription subscription) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    subscription.gymName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(
                  label: _statusLabel(subscription.status),
                  color: _statusColor(subscription.status),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('الخطة: ${subscription.planName}'),
            Text('الحد الأعلى للأعضاء: ${subscription.membersLimit}'),
            Text('التجديد القادم: ${subscription.nextBillingDate}'),
            Text('القيمة الشهرية: ${subscription.monthlyPrice} ر.س'),
            const SizedBox(height: 12),
            DropdownButtonFormField<SubscriptionStatus>(
              initialValue: subscription.status,
              decoration: const InputDecoration(labelText: 'حالة الاشتراك'),
              items: const [
                DropdownMenuItem(value: SubscriptionStatus.active, child: Text('نشط')),
                DropdownMenuItem(value: SubscriptionStatus.paused, child: Text('موقوف')),
                DropdownMenuItem(value: SubscriptionStatus.canceled, child: Text('ملغي')),
              ],
              onChanged: (value) {
                if (value == null) {
                  return;
                }

                _updateStatus(subscription.id, value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _updateStatus(String subscriptionId, SubscriptionStatus status) async {
    try {
      await _api.updateSubscriptionStatus(subscriptionId, status);
      _reload();
      _showResult('تم تحديث حالة الاشتراك');
    } catch (_) {
      _showResult('فشل تحديث حالة الاشتراك');
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _subscriptionsFuture = _api.fetchSubscriptions();
    });

    await _subscriptionsFuture;
  }

  void _reload() {
    setState(() {
      _subscriptionsFuture = _api.fetchSubscriptions();
    });
  }

  void _showResult(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _statusLabel(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.active:
        return 'نشط';
      case SubscriptionStatus.paused:
        return 'موقوف';
      case SubscriptionStatus.canceled:
        return 'ملغي';
    }
  }

  Color _statusColor(SubscriptionStatus status) {
    switch (status) {
      case SubscriptionStatus.active:
        return const Color(0xFF047857);
      case SubscriptionStatus.paused:
        return const Color(0xFFB45309);
      case SubscriptionStatus.canceled:
        return const Color(0xFFB91C1C);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.error_outline, size: 42, color: Colors.red.shade700),
        const SizedBox(height: 10),
        const Text('تعذر تحميل الاشتراكات', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
