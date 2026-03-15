import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';

class OwnerAnalyticsPage extends StatefulWidget {
  const OwnerAnalyticsPage({super.key, this.session});

  final AuthSession? session;

  @override
  State<OwnerAnalyticsPage> createState() => _OwnerAnalyticsPageState();
}

class _OwnerAnalyticsPageState extends State<OwnerAnalyticsPage> {
  late final MarketplaceApiService _api;
  late Future<_AnalyticsData> _future;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
    _future = _loadData();
  }

  Future<_AnalyticsData> _loadData() async {
    final results = await Future.wait<dynamic>([
      _api.fetchOwnerDashboard(),
      _api.fetchOwnerRetention(),
      _api.fetchOwnerGyms(),
    ]);

    return _AnalyticsData(
      dashboard: results[0] as OwnerDashboardSummary,
      retention: results[1] as OwnerRetentionSummary,
      gyms: results[2] as List<GymSummary>,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _loadData();
    });
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_AnalyticsData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError || snapshot.data == null) {
            return _ErrorState(onRetry: _refresh);
          }

          final data = snapshot.data!;
          final topGyms = [...data.gyms]
            ..sort((a, b) => b.averageRating.compareTo(a.averageRating));

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
                16, 16, 16, 24),
            children: [
              Text('تحليلات المالك',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.cardLime,
                      )),
              const SizedBox(height: 8),
              Text(
                'مؤشرات الاحتفاظ والإشغال والتقييمات.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.textSecondary,
                    ),
              ),
              const SizedBox(height: 14),
              _ProgressCard(
                title: 'معدل الاحتفاظ (${data.retention.month})',
                valueText:
                    '${data.retention.retentionPercent.toStringAsFixed(1)}%',
                progress: data.retention.retentionPercent / 100,
                color: AppTheme.cardLime,
              ),
              const SizedBox(height: 10),
              _ProgressCard(
                title: 'معدل التسرب',
                valueText: '${data.retention.churnPercent.toStringAsFixed(1)}%',
                progress: data.retention.churnPercent / 100,
                color: AppTheme.cardPink,
              ),
              const SizedBox(height: 14),
              // ── Key metrics card with lavender accent ──
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  color: AppTheme.cardLavender.withValues(alpha: 0.10),
                  border: Border.all(
                    color: AppTheme.cardLavender.withValues(alpha: 0.20),
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
                          child: const Icon(Icons.insights_rounded,
                              color: Color(0xFF1A1A24), size: 22),
                        ),
                        const SizedBox(width: 12),
                        Text('مؤشرات رئيسية',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: AppTheme.cardLavender)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _MetricLine(
                      label: 'الأعضاء المعرضون للخطر',
                      value: '${data.retention.predictedAtRisk}',
                    ),
                    const SizedBox(height: 8),
                    _MetricLine(
                      label: 'الإشغال الحالي',
                      value: '${data.dashboard.occupancyRate}%',
                    ),
                    const SizedBox(height: 8),
                    _MetricLine(
                      label: 'تقييم المنظومة',
                      value: data.dashboard.averageRating.toStringAsFixed(1),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('أفضل النوادي حسب التقييم',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: AppTheme.cardLavender)),
              const SizedBox(height: 8),
              if (topGyms.isEmpty)
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: AppTheme.cardSurfaceHigh,
                  ),
                  child: const Text(
                    'لا توجد بيانات نوادٍ كافية لعرض المقارنة.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
              ...topGyms.take(5).toList().asMap().entries.map(
                (entry) {
                  final idx = entry.key;
                  final gym = entry.value;
                  const accents = [
                    AppTheme.cardLime,
                    AppTheme.cardLavender,
                    AppTheme.cardPink,
                  ];
                  final accent = accents[idx % accents.length];

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: accent.withValues(alpha: 0.08),
                      border: Border.all(
                        color: accent.withValues(alpha: 0.15),
                        width: 0.5,
                      ),
                    ),
                    child: ListTile(
                      title: Text(
                        gym.name,
                        style: TextStyle(color: accent),
                      ),
                      subtitle: Text(
                        'أعضاء ${gym.membersCount} • مدربون ${gym.trainersCount}',
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                      trailing: Text(
                        '${gym.averageRating.toStringAsFixed(1)} ⭐',
                        style: const TextStyle(color: AppTheme.textPrimary),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }
}

class _AnalyticsData {
  const _AnalyticsData({
    required this.dashboard,
    required this.retention,
    required this.gyms,
  });

  final OwnerDashboardSummary dashboard;
  final OwnerRetentionSummary retention;
  final List<GymSummary> gyms;
}

class _ProgressCard extends StatelessWidget {
  const _ProgressCard({
    required this.title,
    required this.valueText,
    required this.progress,
    required this.color,
  });

  final String title;
  final String valueText;
  final double progress;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: color.withValues(alpha: 0.10),
        border: Border.all(
          color: color.withValues(alpha: 0.20),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: color)),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress.clamp(0, 1),
              minHeight: 10,
              color: color,
              backgroundColor: color.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 8),
          Text(valueText,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: AppTheme.textPrimary)),
        ],
      ),
    );
  }
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({
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
        Text(
          value,
          style: const TextStyle(color: AppTheme.textPrimary),
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
        const Text('تعذر تحميل التحليلات',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
