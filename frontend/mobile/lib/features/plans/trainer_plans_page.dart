import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import 'plans_api_service.dart';

class TrainerPlansPage extends StatefulWidget {
  const TrainerPlansPage({super.key, required this.session});
  final AuthSession? session;
  @override
  State<TrainerPlansPage> createState() => _TrainerPlansPageState();
}

class _TrainerPlansPageState extends State<TrainerPlansPage> {
  late final PlansApiService _api;
  late Future<_TrainerPlansData> _dataFuture;

  bool _isSubmitting = false;
  String? _selectedTraineeId;

  // ── Subscription plan composer state ──────────────────────────
  final TextEditingController _planNameCtrl = TextEditingController();
  final TextEditingController _planPriceCtrl = TextEditingController();
  final TextEditingController _planDescCtrl = TextEditingController();
  int _planDurationMonths = 1;
  bool _subPlanExpanded = false;
  bool _isCreatingPlan = false;

  // ── Structured plan builder state (same as user_plans_page) ───
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_WorkoutDay> _days = [];

  @override
  void initState() {
    super.initState();
    _api = PlansApiService(role: AppRole.trainer, session: widget.session);
    _dataFuture = _loadData();
    _addDay(); // start with one day
  }

  @override
  void dispose() {
    _planNameCtrl.dispose();
    _planPriceCtrl.dispose();
    _planDescCtrl.dispose();
    _titleController.dispose();
    _notesController.dispose();
    for (final d in _days) {
      d.dispose();
    }
    super.dispose();
  }

  // ── Day/Exercise helpers ───────────────────────────────────────
  void _addDay() {
    setState(() => _days.add(_WorkoutDay()));
  }

  void _removeDay(int index) {
    setState(() {
      _days[index].dispose();
      _days.removeAt(index);
    });
  }

  /// Serialise the structured plan to JSON content string.
  /// Same format used in user_plans_page.dart so reading/display is unified.
  String _buildContent() {
    final daysJson = _days.asMap().entries.map((entry) {
      final i = entry.key;
      final day = entry.value;
      return {
        'day': day.nameController.text.trim().isEmpty
            ? 'اليوم ${i + 1}'
            : day.nameController.text.trim(),
        'exercises': day.exercises
            .map((ex) {
              final sets = int.tryParse(ex.setsController.text) ?? 0;
              final reps = int.tryParse(ex.repsController.text) ?? 0;
              final rest = int.tryParse(ex.restController.text) ?? 0;
              return {
                'name': ex.nameController.text.trim(),
                if (sets > 0) 'sets': sets,
                if (reps > 0) 'reps': reps,
                if (rest > 0) 'rest': rest,
                if (ex.notesController.text.trim().isNotEmpty)
                  'notes': ex.notesController.text.trim(),
              };
            })
            .where((e) => (e['name'] as String).isNotEmpty)
            .toList(),
      };
    }).toList();

    return jsonEncode({
      'title': _titleController.text.trim().isEmpty
          ? 'خطة تدريبية'
          : _titleController.text.trim(),
      if (_notesController.text.trim().isNotEmpty)
        'description': _notesController.text.trim(),
      'days': daysJson,
    });
  }

  bool get _isValid {
    if (_titleController.text.trim().isEmpty) return false;
    for (final day in _days) {
      for (final ex in day.exercises) {
        if (ex.nameController.text.trim().isNotEmpty) return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_TrainerPlansData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) return _ErrorState(onRetry: _reload);

          final data = snapshot.data ??
              const _TrainerPlansData(
                  clients: [], plans: [], subscriptionPlans: []);
          final clients = data.clients;
          final hasClients = clients.isNotEmpty;

          if (_selectedTraineeId != null &&
              !clients.any((c) => c.id == _selectedTraineeId)) {
            _selectedTraineeId = null;
          }
          _selectedTraineeId ??= hasClients ? clients.first.id : null;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              // ── Subscription plans section ──────────────────
              _buildSubscriptionPlansSection(theme, data.subscriptionPlans),
              const SizedBox(height: 24),

              // ── Training plans header ─────────────────────
              Text('خطط التدريب',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: AppTheme.gold)),
              const SizedBox(height: 4),
              Text(
                'أنشئ خطة تدريبية منظمة بالأيام والتمارين وأرسلها لمتدربيك.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),

              // ── Trainee picker ────────────────────────────
              if (!hasClients)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16162A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.gold.withValues(alpha: 0.15)),
                  ),
                  child: const Text('لا يوجد لديك متدربون نشطون حالياً.',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
              if (hasClients) ...[
                DropdownButtonFormField<String>(
                  initialValue: _selectedTraineeId,
                  decoration: InputDecoration(
                    labelText: 'اختر المتدرب',
                    prefixIcon: const Icon(Icons.person_outline, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  items: clients
                      .map((c) => DropdownMenuItem<String>(
                            value: c.id,
                            child: Text('${c.name} (${c.gymId})'),
                          ))
                      .toList(growable: false),
                  onChanged: (v) => setState(() => _selectedTraineeId = v),
                ),
              ],
              const SizedBox(height: 16),

              // ── Structured plan builder ───────────────────
              _PlanBuilderSection(
                titleController: _titleController,
                notesController: _notesController,
                days: _days,
                onAddDay: _addDay,
                onRemoveDay: _removeDay,
                onAddExercise: (dayIndex) =>
                    setState(() => _days[dayIndex].exercises.add(_Exercise())),
                onRemoveExercise: (dayIndex, exIndex) => setState(() {
                  _days[dayIndex].exercises[exIndex].dispose();
                  _days[dayIndex].exercises.removeAt(exIndex);
                }),
                onStateChanged: () => setState(() {}),
              ),
              const SizedBox(height: 14),

              // ── Send button ───────────────────────────────
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: (!hasClients || _isSubmitting || !_isValid)
                      ? null
                      : _sendPlan,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send_outlined, size: 18),
                  label: const Text('إرسال الخطة للمتدرب'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.gold,
                    foregroundColor: AppTheme.textOnGold,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              // ── Sent plans history ────────────────────────
              const SizedBox(height: 28),
              _SectionLabel(
                icon: Icons.history_outlined,
                label: 'الخطط المرسلة (${data.plans.length})',
                color: AppTheme.gold,
              ),
              const SizedBox(height: 8),
              if (data.plans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16162A),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppTheme.gold.withValues(alpha: 0.15)),
                  ),
                  child: const Text('لم ترسل أي خطة بعد.',
                      style: TextStyle(color: AppTheme.textSecondary)),
                ),
              ...data.plans.map((plan) => _SentPlanCard(plan: plan)),
            ],
          );
        },
      ),
    );
  }

  // ── Subscription plans section ──────────────────────────────────

  Widget _buildSubscriptionPlansSection(
      ThemeData theme, List<TrainerSubscriptionPlan> plans) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _subPlanExpanded = !_subPlanExpanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.card_membership_outlined,
                      color: AppTheme.gold, size: 17),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('خطط الاشتراك الشهرية',
                            style: theme.textTheme.titleMedium?.copyWith(
                                color: AppTheme.gold,
                                fontWeight: FontWeight.w700)),
                        Text(
                          plans.isEmpty
                              ? 'لا توجد خطط — اضغط لإضافة خطة'
                              : '${plans.length} خطة متاحة',
                          style: theme.textTheme.labelSmall
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                      ]),
                ),
                AnimatedRotation(
                  turns: _subPlanExpanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  child: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppTheme.textMuted, size: 22),
                ),
              ]),
            ),
          ),
          if (plans.isNotEmpty) ...[
            Divider(height: 1, color: AppTheme.gold.withValues(alpha: 0.10)),
            ...plans.map((p) =>
                _SubPlanTile(plan: p, onDelete: () => _deletePlan(p.planId))),
          ],
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: _buildPlanComposer(theme),
            crossFadeState: _subPlanExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
          ),
        ],
      ),
    );
  }

  Widget _buildPlanComposer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Divider(height: 20, color: AppTheme.gold.withValues(alpha: 0.10)),
        Text('إضافة خطة جديدة',
            style: theme.textTheme.labelLarge
                ?.copyWith(color: AppTheme.textSecondary)),
        const SizedBox(height: 10),
        TextField(
          controller: _planNameCtrl,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'اسم الخطة',
            hintText: 'مثال: باقة شهرية أساسية',
            prefixIcon: Icon(Icons.label_outline, size: 18),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _planPriceCtrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'السعر (د.ع)',
            prefixIcon: Icon(Icons.payments_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.calendar_month_outlined,
              size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 6),
          Text('المدة:',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: AppTheme.textSecondary)),
          const Spacer(),
          ...[1, 2, 3, 6, 12].map((m) {
            final sel = _planDurationMonths == m;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setState(() => _planDurationMonths = m),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppTheme.gold
                        : AppTheme.gold.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: sel
                            ? AppTheme.gold
                            : AppTheme.gold.withValues(alpha: 0.20)),
                  ),
                  child: Text(
                    m == 12 ? 'سنة' : '$mش',
                    style: TextStyle(
                      color: sel ? AppTheme.textOnGold : AppTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            );
          }),
        ]),
        const SizedBox(height: 8),
        TextField(
          controller: _planDescCtrl,
          textAlign: TextAlign.right,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'وصف (اختياري)',
            prefixIcon: Icon(Icons.notes_outlined, size: 18),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 44,
          child: ElevatedButton.icon(
            onPressed: _isCreatingPlan ? null : _createPlan,
            icon: _isCreatingPlan
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.add_rounded, size: 18),
            label: const Text('إضافة الخطة'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.gold,
              foregroundColor: AppTheme.textOnGold,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
          ),
        ),
      ]),
    );
  }

  // ── Actions ─────────────────────────────────────────────────────

  Future<void> _createPlan() async {
    final name = _planNameCtrl.text.trim();
    final priceStr = _planPriceCtrl.text.trim();
    if (name.isEmpty) {
      _showMessage('أدخل اسم الخطة');
      return;
    }
    final price = double.tryParse(priceStr);
    if (price == null || price < 0) {
      _showMessage('أدخل سعراً صحيحاً');
      return;
    }
    setState(() => _isCreatingPlan = true);
    try {
      await _api.createSubscriptionPlan(
        name: name,
        price: price,
        durationMonths: _planDurationMonths,
        description: _planDescCtrl.text.trim(),
      );
      _planNameCtrl.clear();
      _planPriceCtrl.clear();
      _planDescCtrl.clear();
      setState(() {
        _subPlanExpanded = false;
        _planDurationMonths = 1;
      });
      _showMessage('تم إنشاء الخطة ✓');
      _reload();
    } catch (_) {
      _showMessage('تعذر إنشاء الخطة');
    } finally {
      if (mounted) setState(() => _isCreatingPlan = false);
    }
  }

  Future<void> _deletePlan(String planId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الخطة'),
        content: const Text('هل أنت متأكد من حذف هذه الخطة؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteSubscriptionPlan(planId);
      _showMessage('تم حذف الخطة');
      _reload();
    } catch (_) {
      _showMessage('تعذر حذف الخطة');
    }
  }

  Future<void> _sendPlan() async {
    final traineeUserId = _selectedTraineeId;
    if (traineeUserId == null || traineeUserId.isEmpty) {
      _showMessage('اختر المتدرب أولاً');
      return;
    }
    if (!_isValid) {
      _showMessage('أدخل اسم الخطة وتمريناً واحداً على الأقل');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final content = _buildContent();
      await _api.sendTrainerPlan(
          traineeUserId: traineeUserId, content: content);
      // Reset builder
      setState(() {
        _titleController.clear();
        _notesController.clear();
        for (final d in _days) {
          d.dispose();
        }
        _days
          ..clear()
          ..add(_WorkoutDay());
      });
      _showMessage('تم إرسال الخطة للمتدرب ✓');
      _reload();
    } catch (_) {
      _showMessage('تعذر إرسال الخطة (تأكد من أن المتدرب نشط لديك)');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<_TrainerPlansData> _loadData() async {
    final results = await Future.wait([
      _api.fetchTrainerClients(),
      _api.fetchMyPlans(),
      _api.fetchMySubscriptionPlans(),
    ]);
    return _TrainerPlansData(
      clients: results[0] as List<TrainerClientSummary>,
      plans: (results[1] as List<PlanItem>)
          .where((p) => p.type == 'TRAINER_TO_TRAINEE')
          .toList(growable: false),
      subscriptionPlans: results[2] as List<TrainerSubscriptionPlan>,
    );
  }

  Future<void> _refresh() async {
    setState(() => _dataFuture = _loadData());
    await _dataFuture;
  }

  void _reload() => setState(() => _dataFuture = _loadData());

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Structured Plan Builder (unified with user_plans_page pattern)
// ═════════════════════════════════════════════════════════════════════════════

class _Exercise {
  final nameController = TextEditingController();
  final setsController = TextEditingController();
  final repsController = TextEditingController();
  final restController = TextEditingController();
  final notesController = TextEditingController();

  void dispose() {
    nameController.dispose();
    setsController.dispose();
    repsController.dispose();
    restController.dispose();
    notesController.dispose();
  }
}

class _WorkoutDay {
  final nameController = TextEditingController();
  final List<_Exercise> exercises = [_Exercise()];

  void dispose() {
    nameController.dispose();
    for (final e in exercises) {
      e.dispose();
    }
  }
}

class _PlanBuilderSection extends StatelessWidget {
  const _PlanBuilderSection({
    required this.titleController,
    required this.notesController,
    required this.days,
    required this.onAddDay,
    required this.onRemoveDay,
    required this.onAddExercise,
    required this.onRemoveExercise,
    required this.onStateChanged,
  });

  final TextEditingController titleController;
  final TextEditingController notesController;
  final List<_WorkoutDay> days;
  final VoidCallback onAddDay;
  final void Function(int dayIndex) onRemoveDay;
  final void Function(int dayIndex) onAddExercise;
  final void Function(int dayIndex, int exIndex) onRemoveExercise;
  final VoidCallback onStateChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Plan title
        TextField(
          controller: titleController,
          onChanged: (_) => onStateChanged(),
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            labelText: 'اسم الخطة التدريبية *',
            hintText: 'مثال: خطة القوة – 4 أسابيع',
            prefixIcon: const Icon(Icons.title_outlined),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 10),
        // Optional notes
        TextField(
          controller: notesController,
          minLines: 2,
          maxLines: 3,
          textAlign: TextAlign.right,
          decoration: InputDecoration(
            labelText: 'ملاحظات عامة (اختياري)',
            hintText:
                'مثال: الراحة بين الجولات 60 ثانية، التركيز على الشكل الصحيح...',
            prefixIcon: const Icon(Icons.notes_outlined),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),

        // Days
        ...days.asMap().entries.map((entry) {
          final i = entry.key;
          final day = entry.value;
          return _DayCard(
            dayIndex: i,
            day: day,
            canRemove: days.length > 1,
            onRemoveDay: () => onRemoveDay(i),
            onAddExercise: () => onAddExercise(i),
            onRemoveExercise: (exIndex) => onRemoveExercise(i, exIndex),
            onStateChanged: onStateChanged,
          );
        }),

        // Add day button
        OutlinedButton.icon(
          onPressed: onAddDay,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('إضافة يوم'),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.gold,
            side: BorderSide(color: AppTheme.gold.withValues(alpha: 0.5)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.dayIndex,
    required this.day,
    required this.canRemove,
    required this.onRemoveDay,
    required this.onAddExercise,
    required this.onRemoveExercise,
    required this.onStateChanged,
  });

  final int dayIndex;
  final _WorkoutDay day;
  final bool canRemove;
  final VoidCallback onRemoveDay;
  final VoidCallback onAddExercise;
  final void Function(int exIndex) onRemoveExercise;
  final VoidCallback onStateChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Day header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                if (canRemove)
                  IconButton(
                    onPressed: onRemoveDay,
                    icon: Icon(Icons.remove_circle_outline,
                        size: 18, color: Colors.red.shade400),
                    visualDensity: VisualDensity.compact,
                    tooltip: 'حذف اليوم',
                  ),
                const Spacer(),
                Expanded(
                  flex: 6,
                  child: TextField(
                    controller: day.nameController,
                    onChanged: (_) => onStateChanged(),
                    textAlign: TextAlign.right,
                    style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      hintText: 'اليوم ${dayIndex + 1} – مثال: صدر وترايسبس',
                      hintStyle: theme.textTheme.bodySmall
                          ?.copyWith(color: AppTheme.textMuted),
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${dayIndex + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: AppTheme.gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),

          // Exercise rows header
          const Padding(
            padding: EdgeInsets.fromLTRB(14, 10, 14, 4),
            child: Row(
              children: [
                SizedBox(width: 28),
                _FixedColHeader('راحة\n(ث)', width: 72),
                SizedBox(width: 4),
                _FixedColHeader('تكرار', width: 72),
                SizedBox(width: 4),
                _FixedColHeader('جولات', width: 72),
                SizedBox(width: 4),
                Expanded(
                    child: Align(
                  alignment: Alignment.center,
                  child: Text('التمرين',
                      style: TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                )),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.gold.withValues(alpha: 0.10)),

          // Exercises
          ...day.exercises.asMap().entries.map((entry) {
            final exIndex = entry.key;
            final ex = entry.value;
            return _ExerciseRow(
              exercise: ex,
              canRemove: day.exercises.length > 1,
              onRemove: () => onRemoveExercise(exIndex),
              onChanged: onStateChanged,
            );
          }),

          // Add exercise
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
            child: GestureDetector(
              onTap: onAddExercise,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text('إضافة تمرين',
                      style: theme.textTheme.labelMedium
                          ?.copyWith(color: AppTheme.gold)),
                  const SizedBox(width: 4),
                  const Icon(Icons.add_circle_outline,
                      size: 16, color: AppTheme.gold),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FixedColHeader extends StatelessWidget {
  const _FixedColHeader(this.label, {required this.width});
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppTheme.textMuted,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  const _ExerciseRow({
    required this.exercise,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final _Exercise exercise;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  static const double _kDeleteWidth = 28;
  static const double _kNumberWidth = 72;
  static const double _kGap = 4;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
      child: Row(
        children: [
          // Delete
          SizedBox(
            width: _kDeleteWidth,
            child: canRemove
                ? GestureDetector(
                    onTap: onRemove,
                    child: Icon(Icons.close,
                        size: 16, color: Colors.red.shade400),
                  )
                : null,
          ),

          SizedBox(
            width: _kNumberWidth,
            child: _WheelNumberField.seconds(
              controller: exercise.restController,
              hint: 60,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: _kGap),

          SizedBox(
            width: _kNumberWidth,
            child: _WheelNumberField.reps(
              controller: exercise.repsController,
              hint: 12,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: _kGap),

          SizedBox(
            width: _kNumberWidth,
            child: _WheelNumberField.sets(
              controller: exercise.setsController,
              hint: 3,
              onChanged: onChanged,
            ),
          ),
          const SizedBox(width: _kGap),

          // Name
          Expanded(
            child: _CompactField(
              controller: exercise.nameController,
              hint: 'اسم التمرين',
              textAlign: TextAlign.right,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Wheel picker for sets / reps / rest — same as user_plans_page.
class _WheelNumberField extends StatelessWidget {
  const _WheelNumberField({
    required this.controller,
    required this.values,
    required this.hint,
    this.suffix,
    this.onChanged,
  });

  final TextEditingController controller;
  final List<int> values;
  final int hint;
  final String? suffix;
  final VoidCallback? onChanged;

  factory _WheelNumberField.sets({
    required TextEditingController controller,
    int hint = 3,
    VoidCallback? onChanged,
  }) {
    return _WheelNumberField(
      controller: controller,
      values: List<int>.generate(20, (i) => i + 1),
      hint: hint,
      onChanged: onChanged,
    );
  }

  factory _WheelNumberField.reps({
    required TextEditingController controller,
    int hint = 12,
    VoidCallback? onChanged,
  }) {
    return _WheelNumberField(
      controller: controller,
      values: List<int>.generate(40, (i) => i + 1),
      hint: hint,
      onChanged: onChanged,
    );
  }

  factory _WheelNumberField.seconds({
    required TextEditingController controller,
    int hint = 60,
    VoidCallback? onChanged,
  }) {
    final vals = <int>[];
    for (var s = 15; s <= 300; s += 15) {
      vals.add(s);
    }
    return _WheelNumberField(
      controller: controller,
      values: vals,
      hint: hint,
      suffix: 'ث',
      onChanged: onChanged,
    );
  }

  int? _currentValue() {
    final t = controller.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = _currentValue();
    final displayValue = current ?? hint;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showWheel(context),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF1C1C34),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  suffix == null ? '$displayValue' : '$displayValue $suffix',
                  style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.unfold_more_rounded,
                  size: 18, color: AppTheme.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showWheel(BuildContext context) async {
    final theme = Theme.of(context);

    final current = _currentValue();
    final initial = (current != null && values.contains(current))
        ? values.indexOf(current)
        : values.indexOf(hint).clamp(0, values.length - 1);

    int selectedIndex = initial;

    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (ctx) {
        return SafeArea(
          child: SizedBox(
            height: 320,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(null),
                        child: const Text('إلغاء'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () =>
                            Navigator.of(ctx).pop(values[selectedIndex]),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppTheme.gold,
                          foregroundColor: AppTheme.textOnGold,
                        ),
                        child: const Text('اختيار'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: theme.brightness,
                    ),
                    child: CupertinoPicker(
                      scrollController:
                          FixedExtentScrollController(initialItem: initial),
                      itemExtent: 44,
                      magnification: 1.1,
                      useMagnifier: true,
                      onSelectedItemChanged: (i) => selectedIndex = i,
                      children: values
                          .map(
                            (v) => Center(
                              child: Text(
                                suffix == null ? '$v' : '$v $suffix',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                          )
                          .toList(growable: false),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null) return;
    controller.text = picked.toString();
    onChanged?.call();
  }
}

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.controller,
    required this.hint,
    this.textAlign = TextAlign.center,
    this.onChanged,
  });

  final TextEditingController controller;
  final String hint;
  final TextAlign textAlign;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      onChanged: (_) => onChanged?.call(),
      textAlign: textAlign,
      keyboardType: TextInputType.text,
      style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.gold.withValues(alpha: 0.20)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppTheme.gold.withValues(alpha: 0.20)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppTheme.gold),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Sent plan card – renders structured JSON just like user_plans_page
// ═════════════════════════════════════════════════════════════════════════════

class _SentPlanCard extends StatefulWidget {
  const _SentPlanCard({required this.plan});
  final PlanItem plan;

  @override
  State<_SentPlanCard> createState() => _SentPlanCardState();
}

class _SentPlanCardState extends State<_SentPlanCard> {
  late List<bool> _expanded;
  Map<String, dynamic>? _parsed;
  late String _title;
  late String _description;
  late List _days;

  @override
  void initState() {
    super.initState();
    _parse();
  }

  void _parse() {
    try {
      if (widget.plan.content.trim().startsWith('{')) {
        _parsed = jsonDecode(widget.plan.content) as Map<String, dynamic>?;
      }
    } catch (_) {}
    _title = (_parsed?['title'] as String?) ?? '';
    _description = (_parsed?['description'] as String?) ?? '';
    _days = (_parsed?['days'] as List?) ?? const [];
    _expanded = List.filled(_days.length, false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.06),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                // Date badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.plan.createdAt,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: AppTheme.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'إلى: ${widget.plan.traineeName}',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: AppTheme.textSecondary),
                ),
                const Spacer(),
                Flexible(
                  child: Text(
                    _title.isNotEmpty ? _title : 'خطة تدريبية',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                  ),
                ),
                const SizedBox(width: 10),
                const Icon(Icons.send_outlined, size: 18, color: AppTheme.gold),
              ],
            ),
          ),

          // Description
          if (_description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                _description,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.right,
              ),
            ),

          // Day stat badges
          if (_days.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _InfoTag(
                    icon: Icons.calendar_today_outlined,
                    label:
                        '${_days.length} ${_days.length == 1 ? 'يوم' : 'أيام'}',
                  ),
                  const SizedBox(width: 8),
                  _InfoTag(
                    icon: Icons.fitness_center_outlined,
                    label: '${_days.fold<int>(0, (sum, d) {
                      final exList =
                          (d as Map<String, dynamic>)['exercises'] as List? ??
                              [];
                      return sum + exList.length;
                    })} تمرين',
                  ),
                ],
              ),
            ),
          ],

          // Expandable days
          if (_days.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...List.generate(_days.length, (i) {
              final dayJson = _days[i] as Map<String, dynamic>;
              return _ExpandableDaySection(
                dayJson: dayJson,
                dayIndex: i,
                isExpanded: _expanded[i],
                onToggle: () => setState(() => _expanded[i] = !_expanded[i]),
              );
            }),
            const SizedBox(height: 6),
          ] else if (_title.isEmpty && _description.isEmpty) ...[
            // Raw text fallback for old plain-text plans
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                widget.plan.content,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Expandable day section (for sent plan cards)
// ═════════════════════════════════════════════════════════════════════════════

class _ExpandableDaySection extends StatelessWidget {
  const _ExpandableDaySection({
    required this.dayJson,
    required this.dayIndex,
    required this.isExpanded,
    required this.onToggle,
  });

  final Map<String, dynamic> dayJson;
  final int dayIndex;
  final bool isExpanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dayName = (dayJson['day'] ?? 'اليوم ${dayIndex + 1}').toString();
    final exercises = (dayJson['exercises'] as List?) ?? const [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1C1C34),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.12)),
        ),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(Icons.chevron_right,
                          size: 20, color: AppTheme.gold),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.gold.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${exercises.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.gold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      dayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: AppTheme.gold,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${dayIndex + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: AppTheme.textOnGold,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: isExpanded
                  ? Column(
                      children: [
                        Divider(
                            height: 1,
                            color: AppTheme.gold.withValues(alpha: 0.10)),
                        ...exercises.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final ex = entry.value as Map<String, dynamic>;
                          return _ExerciseDetailRow(
                            ex: ex,
                            index: idx,
                            isLast: idx == exercises.length - 1,
                          );
                        }),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseDetailRow extends StatelessWidget {
  const _ExerciseDetailRow({
    required this.ex,
    required this.index,
    required this.isLast,
  });

  final Map<String, dynamic> ex;
  final int index;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = (ex['name'] ?? '').toString();
    final sets = ex['sets'];
    final reps = ex['reps'];
    final rest = ex['rest'];
    final notes = (ex['notes'] ?? '').toString();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _StatBadge(
                    label: 'راحة',
                    value: rest != null ? '$rest ث' : '--',
                    icon: Icons.timer_outlined,
                  ),
                  const SizedBox(width: 6),
                  _StatBadge(
                    label: 'تكرار',
                    value: reps != null ? '$reps' : '--',
                    icon: Icons.repeat_outlined,
                  ),
                  const SizedBox(width: 6),
                  _StatBadge(
                    label: 'جولات',
                    value: sets != null ? '$sets' : '--',
                    icon: Icons.loop_outlined,
                  ),
                ],
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  notes,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: AppTheme.textMuted),
                  textAlign: TextAlign.right,
                ),
              ],
            ],
          ),
        ),
        if (!isLast)
          Divider(
              height: 1,
              indent: 14,
              endIndent: 14,
              color: AppTheme.gold.withValues(alpha: 0.08)),
      ],
    );
  }
}

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.gold,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: AppTheme.textMuted),
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 13, color: AppTheme.gold),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Shared widgets
// ═════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600, color: color)),
      ],
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
        color: AppTheme.gold.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppTheme.textMuted),
          const SizedBox(width: 4),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Subscription plan tile
// ═════════════════════════════════════════════════════════════════════════════

class _SubPlanTile extends StatelessWidget {
  const _SubPlanTile({required this.plan, required this.onDelete});
  final TrainerSubscriptionPlan plan;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        IconButton(
          icon: Icon(Icons.delete_outline_rounded,
              size: 18, color: Colors.red.shade400),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
        ),
        const Spacer(),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(plan.name,
              style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                  fontSize: 14)),
          const SizedBox(height: 3),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(plan.durationLabel,
                style:
                    const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('${plan.price.toStringAsFixed(0)} د.ع',
                  style: const TextStyle(
                      color: AppTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          if (plan.description.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(plan.description,
                style: const TextStyle(color: AppTheme.textMuted, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ]),
        const SizedBox(width: 10),
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppTheme.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.card_membership_outlined,
              color: AppTheme.gold, size: 18),
        ),
      ]),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Data + error
// ═════════════════════════════════════════════════════════════════════════════

class _TrainerPlansData {
  const _TrainerPlansData({
    required this.clients,
    required this.plans,
    required this.subscriptionPlans,
  });
  final List<TrainerClientSummary> clients;
  final List<PlanItem> plans;
  final List<TrainerSubscriptionPlan> subscriptionPlans;
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
        const SizedBox(height: 40),
        const Icon(Icons.error_outline, size: 42, color: Colors.redAccent),
        const SizedBox(height: 10),
        const Text('تعذر تحميل خطط المدرب',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('إعادة المحاولة'),
            style: OutlinedButton.styleFrom(foregroundColor: AppTheme.gold),
          ),
        ),
      ],
    );
  }
}
