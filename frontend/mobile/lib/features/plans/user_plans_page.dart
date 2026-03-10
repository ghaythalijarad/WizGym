import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import 'plans_api_service.dart';

class UserPlansPage extends StatefulWidget {
  const UserPlansPage({super.key, required this.session});

  final AuthSession? session;

  @override
  State<UserPlansPage> createState() => _UserPlansPageState();
}

class _UserPlansPageState extends State<UserPlansPage> {
  late final PlansApiService _api;
  late Future<List<PlanItem>> _plansFuture;
  final TextEditingController _planController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _api = PlansApiService(role: AppRole.trainee, session: widget.session);
    _plansFuture = _api.fetchMyPlans();
  }

  @override
  void dispose() {
    _planController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<PlanItem>>(
        future: _plansFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _ErrorState(onRetry: _reload, title: 'تعذر تحميل الخطط');
          }

          final plans = snapshot.data ?? const <PlanItem>[];
          final trainerPlans =
              plans.where((p) => p.isFromTrainer).toList(growable: false);
          final myPlans =
              plans.where((p) => !p.isFromTrainer).toList(growable: false);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom + 80),
            children: [
              Text('خططي',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: AppTheme.cardLime)),
              const SizedBox(height: 8),
              Text(
                'يمكنك كتابة خطة نصية خاصة بك، وستظهر لك أيضًا خطط المدرب المرسلة إليك.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _planController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'اكتب خطة نصية',
                  hintText: 'مثال: يوم الأحد صدر + تراي، 4 تمارين، 3 جولات...',
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: _isSubmitting ? null : _createOwnPlan,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.note_add_outlined),
                  label: const Text('حفظ خطتي'),
                ),
              ),

              // ── Trainer plans section ──────────────────────────────────
              if (trainerPlans.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Icon(Icons.sports_outlined,
                        color: AppTheme.cardLavender, size: 20),
                    const SizedBox(width: 8),
                    Text('خطط من المدرب (${trainerPlans.length})',
                        style: theme.textTheme.titleLarge
                            ?.copyWith(color: AppTheme.cardLavender)),
                  ],
                ),
                const SizedBox(height: 8),
                ...trainerPlans.map((p) => _TrainerPlanCard(plan: p)),
              ],

              // ── My own plans section ───────────────────────────────────
              const SizedBox(height: 24),
              Text('خططي الشخصية (${myPlans.length})',
                  style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (myPlans.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text('لا توجد خطط شخصية بعد.',
                        style: TextStyle(color: scheme.onSurfaceVariant)),
                  ),
                ),
              ...myPlans.map((p) => _MyPlanCard(plan: p, theme: theme)),
            ],
          );
        },
      ),
    );
  }

  Future<void> _createOwnPlan() async {
    final content = _planController.text.trim();
    if (content.length < 3) {
      _showMessage('اكتب خطة لا تقل عن 3 أحرف');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      await _api.createTraineePlan(content);
      _planController.clear();
      _showMessage('تم حفظ الخطة بنجاح');
      _reload();
    } catch (_) {
      _showMessage('تعذر حفظ الخطة');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _refresh() async {
    setState(() => _plansFuture = _api.fetchMyPlans());
    await _plansFuture;
  }

  void _reload() => setState(() => _plansFuture = _api.fetchMyPlans());

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TrainerPlanCard extends StatelessWidget {
  const _TrainerPlanCard({required this.plan});
  final PlanItem plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Map<String, dynamic>? parsed;
    try {
      final raw = plan.content;
      if (raw.trim().startsWith('{')) {
        parsed = jsonDecode(raw) as Map<String, dynamic>?;
      }
    } catch (_) {}

    final title = parsed?['title'] as String? ?? '';
    final description = parsed?['description'] as String? ?? '';
    final exercises = (parsed?['exercises'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const <String>[];
    final durationDays = parsed?['durationDays'];
    final frequency = parsed?['frequency'] as String? ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
            color: AppTheme.cardLavender.withValues(alpha: 0.45), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor:
                      AppTheme.cardLavender.withValues(alpha: 0.18),
                  child: const Icon(Icons.sports_outlined,
                      color: AppTheme.cardLavender, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isNotEmpty ? title : 'خطة تدريبية',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        'من المدرب  •  ${plan.createdAt}',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color:
                                AppTheme.cardLavender.withValues(alpha: 0.8)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(description, style: theme.textTheme.bodyMedium),
            ],
            if (exercises.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text('التمارين',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppTheme.textSecondary)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: exercises
                    .map((e) => Chip(
                          label: Text(e, style: const TextStyle(fontSize: 12)),
                          visualDensity: VisualDensity.compact,
                        ))
                    .toList(growable: false),
              ),
            ],
            if (durationDays != null || frequency.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 10,
                children: [
                  if (durationDays != null)
                    _InfoTag(
                        icon: Icons.calendar_month_outlined,
                        label: '$durationDays يوم'),
                  if (frequency.isNotEmpty)
                    _InfoTag(icon: Icons.repeat_outlined, label: frequency),
                ],
              ),
            ],
            if (title.isEmpty && description.isEmpty && exercises.isEmpty) ...[
              const SizedBox(height: 8),
              Text(plan.content, style: theme.textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }
}

class _MyPlanCard extends StatelessWidget {
  const _MyPlanCard({required this.plan, required this.theme});
  final PlanItem plan;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text('خطتي الشخصية',
                        style: theme.textTheme.titleMedium)),
                Text(plan.createdAt, style: theme.textTheme.bodySmall),
              ],
            ),
            const SizedBox(height: 8),
            Text(plan.content, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _InfoTag extends StatelessWidget {
  const _InfoTag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.textSecondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.textSecondary),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry, required this.title});
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.error_outline, size: 42, color: AppTheme.cardPink),
        const SizedBox(height: 10),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
