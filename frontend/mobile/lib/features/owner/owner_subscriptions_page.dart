import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';

class OwnerSubscriptionsPage extends StatefulWidget {
  const OwnerSubscriptionsPage({super.key, this.session});

  final AuthSession? session;

  @override
  State<OwnerSubscriptionsPage> createState() => _OwnerSubscriptionsPageState();
}

class _OwnerSubscriptionsPageState extends State<OwnerSubscriptionsPage> {
  late final MarketplaceApiService _api;
  late Future<List<GymSummary>> _future;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
    _future = _api.fetchOwnerGyms();
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _api.fetchOwnerGyms();
    });
    await _future;
  }

  void _showActionMessage(String text) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<GymSummary>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(onRetry: _refresh);
          }

          final gyms = snapshot.data ?? const <GymSummary>[];
          final subscriptions =
              gyms.map(_SubscriptionView.fromGym).toList(growable: false);
          final totalMonthly = subscriptions.fold<int>(
              0, (sum, item) => sum + item.monthlyPrice);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom + 80),
            children: [
              Text('إدارة الاشتراكات',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.cardLime,
                      )),
              const SizedBox(height: 8),
              Text(
                'خطة كل نادي + تقدير الفاتورة الشهرية الحالية.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              // ── Summary card with lavender accent ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: AppTheme.cardLavender.withValues(alpha: 0.12),
                  border: Border.all(
                    color: AppTheme.cardLavender.withValues(alpha: 0.25),
                    width: 0.5,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppTheme.cardLavender,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.dashboard_rounded,
                              color: Color(0xFF1A1A24), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text('ملخص الاشتراكات',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: AppTheme.cardLavender)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SummaryLine(
                        label: 'عدد النوادي', value: '${subscriptions.length}'),
                    const SizedBox(height: 6),
                    _SummaryLine(
                        label: 'إجمالي التقدير الشهري',
                        value: '$totalMonthly د.ع'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (subscriptions.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: AppTheme.cardSurfaceHigh,
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.storefront_outlined,
                          size: 42, color: AppTheme.textSecondary),
                      SizedBox(height: 10),
                      Text(
                        'لا توجد اشتراكات لأن حساب المالك لا يملك نوادٍ حالياً.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
              ...subscriptions.asMap().entries.map(
                (entry) {
                  final idx = entry.key;
                  final subscription = entry.value;
                  // Cycle: lime → lavender → pink
                  const accents = [
                    AppTheme.cardLime,
                    AppTheme.cardLavender,
                    AppTheme.cardPink,
                  ];
                  final accent = accents[idx % accents.length];
                  final accentFg =
                      ThemeData.estimateBrightnessForColor(accent) ==
                              Brightness.light
                          ? const Color(0xFF0E0E12)
                          : Colors.white;

                  return Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: accent.withValues(alpha: 0.10),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.20),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 42,
                              height: 42,
                              decoration: BoxDecoration(
                                color: accent,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(Icons.fitness_center_rounded,
                                  color: accentFg, size: 22),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(subscription.gymName,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(color: accent)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        _InfoChip(label: 'الخطة', value: subscription.planName),
                        const SizedBox(height: 6),
                        _InfoChip(
                            label: 'الحد',
                            value: '${subscription.membersLimit} عضو'),
                        const SizedBox(height: 6),
                        _InfoChip(
                            label: 'الأعضاء الحاليون',
                            value: '${subscription.currentMembers}'),
                        const SizedBox(height: 6),
                        _InfoChip(
                            label: 'السعر الشهري',
                            value: '${subscription.monthlyPrice} د.ع'),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: () => _showActionMessage(
                                  'تم إرسال طلب ترقية خطة ${subscription.gymName}'),
                              style: FilledButton.styleFrom(
                                backgroundColor: accent,
                                foregroundColor: accentFg,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 18),
                              ),
                              child: const Text('طلب ترقية'),
                            ),
                            OutlinedButton(
                              onPressed: () => _showActionMessage(
                                  'تم إرسال طلب تجميد مؤقت لـ ${subscription.gymName}'),
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(
                                    color: accent.withValues(alpha: 0.5)),
                                foregroundColor: accent,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 18),
                              ),
                              child: const Text('تجميد مؤقت'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
              // extra spacing so content is not hidden behind bottom nav
              const SizedBox(height: 80),
            ],
          );
        },
      ),
    );
  }
}

class _SubscriptionView {
  const _SubscriptionView({
    required this.gymName,
    required this.planName,
    required this.membersLimit,
    required this.currentMembers,
    required this.monthlyPrice,
  });

  final String gymName;
  final String planName;
  final int membersLimit;
  final int currentMembers;
  final int monthlyPrice;

  factory _SubscriptionView.fromGym(GymSummary gym) {
    if (gym.membersCount <= 400) {
      return _SubscriptionView(
        gymName: gym.name,
        planName: 'Starter',
        membersLimit: 400,
        currentMembers: gym.membersCount,
        monthlyPrice: 499,
      );
    }

    if (gym.membersCount <= 900) {
      return _SubscriptionView(
        gymName: gym.name,
        planName: 'Growth',
        membersLimit: 900,
        currentMembers: gym.membersCount,
        monthlyPrice: 799,
      );
    }

    return _SubscriptionView(
      gymName: gym.name,
      planName: 'Business Pro',
      membersLimit: 1500,
      currentMembers: gym.membersCount,
      monthlyPrice: 1299,
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: AppTheme.textSecondary),
          ),
        ),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(color: AppTheme.textPrimary)),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('$label: ',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: AppTheme.textSecondary)),
        Expanded(
          child: Text(value,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: AppTheme.textPrimary)),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.error_outline, size: 42, color: AppTheme.cardPink),
        const SizedBox(height: 10),
        const Text('تعذر تحميل الاشتراكات',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
