import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../plans/plans_api_service.dart';
import 'trainer_certificates_page.dart';

class TrainerHomePage extends StatefulWidget {
  const TrainerHomePage({super.key, this.session});

  final AuthSession? session;

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
    final session = widget.session ?? await _sessionStore.load();
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
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            children: [
              // ── Greeting ─────────────────────────────────────────────
              if (data.displayName.isNotEmpty) ...[
                RichText(
                  text: TextSpan(
                    style: theme.textTheme.headlineSmall?.copyWith(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                    children: [
                      const TextSpan(text: 'أهلاً، '),
                      TextSpan(
                        text: data.displayName,
                        style: const TextStyle(
                          color: AppTheme.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const TextSpan(text: ' 👋'),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'هنا ملخص نشاطك التدريبي اليوم',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // ── Stats row ────────────────────────────────────────────
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: _StatBlock(
                        value: '${data.activeClients}',
                        label: 'عملاء\nنشطون',
                        icon: Icons.people_alt_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBlock(
                        value: '${data.totalRequests}',
                        label: 'إجمالي\nالطلبات',
                        icon: Icons.list_alt_outlined,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _StatBlock(
                        value: '${data.pendingRequests}',
                        label: 'بانتظار\nالرد',
                        icon: Icons.hourglass_top_outlined,
                        highlight: data.pendingRequests > 0,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TrainerCertificatesPage(
                          session: widget.session,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.verified_outlined, size: 18),
                  label: const Text('الشهادات والأوسمة'),
                ),
              ),

              const SizedBox(height: 10),

              // ── Tip card ─────────────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF16162A),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: AppTheme.gold.withValues(alpha: 0.14)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.tips_and_updates_outlined,
                          size: 18, color: AppTheme.gold),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        data.pendingRequests > 0
                            ? 'لديك ${data.pendingRequests} طلب انتظار ردك — تحقق من قسم الاشتراكات'
                            : 'لا توجد طلبات معلقة. استمر في العمل الرائع!',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact stat block used in the 3-column metrics row
// ─────────────────────────────────────────────────────────────────────────────

class _StatBlock extends StatelessWidget {
  const _StatBlock({
    required this.value,
    required this.label,
    required this.icon,
    this.highlight = false,
  });

  final String value;
  final String label;
  final IconData icon;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final accent = highlight ? AppTheme.gold : AppTheme.textSecondary;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlight
              ? AppTheme.gold.withValues(alpha: 0.40)
              : AppTheme.gold.withValues(alpha: 0.10),
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: AppTheme.gold.withValues(alpha: 0.10),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
              ]
            : [],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: accent),
          const SizedBox(height: 8),
          Text(
            value,
            style: tt.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: highlight ? AppTheme.gold : AppTheme.textPrimary,
              height: 1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            textAlign: TextAlign.center,
            style: tt.labelSmall?.copyWith(
              color: AppTheme.textMuted,
              height: 1.3,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

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
