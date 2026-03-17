import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
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
  bool _isSubmitting = false;
  String? _lastDeleteError;

  // ── Structured plan builder state ──────────────────────────────
  final _titleController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_WorkoutDay> _days = [];

  @override
  void initState() {
    super.initState();
    _api = PlansApiService(role: AppRole.trainee, session: widget.session);
    _plansFuture = _api.fetchMyPlans();
    _addDay(); // start with one day
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    for (final d in _days) {
      d.dispose();
    }
    super.dispose();
  }

  void _addDay() {
    setState(() => _days.add(_WorkoutDay()));
  }

  void _removeDay(int index) {
    setState(() {
      _days[index].dispose();
      _days.removeAt(index);
    });
  }

  // Serialise the structured plan to JSON content string
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
          ? 'خطتي التدريبية'
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
            padding: const EdgeInsets.fromLTRB(
                16, 16, 16, 24),
            children: [
              // ── Header ────────────────────────────────────────
              Text('خططي',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: scheme.primary)),
              const SizedBox(height: 4),
              Text(
                'أنشئ خطة تدريبية منظمة بالأيام والتمارين.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 20),

              // ── Plan builder ──────────────────────────────────
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

              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: (_isSubmitting || !_isValid) ? null : _savePlan,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined, size: 18),
                  label: const Text('حفظ الخطة'),
                ),
              ),

              // ── Trainer plans ─────────────────────────────────
              if (trainerPlans.isNotEmpty) ...[
                const SizedBox(height: 28),
                _SectionLabel(
                  icon: Icons.sports_outlined,
                  label: 'خطط من المدرب (${trainerPlans.length})',
                  color: scheme.secondary,
                ),
                const SizedBox(height: 8),
                ...trainerPlans.map((p) => _TrainerPlanCard(plan: p)),
              ],

              // ── My plans ──────────────────────────────────────
              const SizedBox(height: 28),
              _SectionLabel(
                icon: Icons.format_list_bulleted_outlined,
                label: 'خططي الشخصية (${myPlans.length})',
                color: scheme.onSurface,
              ),
              const SizedBox(height: 8),
              if (myPlans.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: scheme.outline),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('لا توجد خطط شخصية بعد.',
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                ),
              ...myPlans.map((p) => _MyPlanCard(
                    plan: p,
                    theme: theme,
                    onDelete: () => _deletePlan(p.id),
                  )),
            ],
          );
        },
      ),
    );
  }

  Future<void> _savePlan() async {
    setState(() => _isSubmitting = true);
    try {
      await _api.createTraineePlan(_buildContent());
      _showMessage('تم حفظ الخطة بنجاح ✓');
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
      _reload();
    } catch (_) {
      _showMessage('تعذر حفظ الخطة');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _deletePlan(String planId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('حذف الخطة'),
          content: const Text('هل أنت متأكد من حذف هذه الخطة نهائياً؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              child: const Text('حذف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    if (mounted) {
      setState(() => _lastDeleteError = null);
    }
    _showMessage('جارٍ حذف الخطة...');

    try {
      await _api.deleteTraineePlan(planId);
      if (!mounted) return;
      _showMessage('تم حذف الخطة');

      // Refresh immediately so the deleted plan disappears without navigating away.
      // Awaiting helps keep RefreshIndicator / UI consistent.
      setState(() => _plansFuture = _api.fetchMyPlans());
      await _plansFuture;
    } catch (e) {
      if (!mounted) return;
      setState(() => _lastDeleteError = e.toString());
      _showMessage('تعذر حذف الخطة: $_lastDeleteError');
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

// ─────────────────────────────────────────────────────────────────────────────
// Data models for the plan builder
// ─────────────────────────────────────────────────────────────────────────────

class _Exercise {
  final nameController = TextEditingController();
  final setsController = TextEditingController(text: '3');
  final repsController = TextEditingController(text: '12');
  final restController = TextEditingController(text: '60');
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

// ─────────────────────────────────────────────────────────────────────────────
// Plan builder section widget
// ─────────────────────────────────────────────────────────────────────────────

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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Plan title
        TextField(
          controller: titleController,
          onChanged: (_) => onStateChanged(),
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'اسم الخطة *',
            hintText: 'مثال: خطة القوة – 4 أسابيع',
            prefixIcon: Icon(Icons.title_outlined),
          ),
        ),
        const SizedBox(height: 10),
        // Optional notes
        TextField(
          controller: notesController,
          minLines: 2,
          maxLines: 3,
          textAlign: TextAlign.right,
          decoration: const InputDecoration(
            labelText: 'ملاحظات عامة (اختياري)',
            hintText:
                'مثال: الراحة بين الجولات 60 ثانية، التركيز على الشكل الصحيح...',
            prefixIcon: Icon(Icons.notes_outlined),
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
            onRemoveExercise: (dayIndex) => onRemoveExercise(i, dayIndex),
            onStateChanged: onStateChanged,
          );
        }),

        // Add day button
        OutlinedButton.icon(
          onPressed: onAddDay,
          icon: const Icon(Icons.add, size: 16),
          label: const Text('إضافة يوم'),
          style: OutlinedButton.styleFrom(
            foregroundColor: scheme.primary,
            side: BorderSide(color: scheme.primary.withAlpha(0x80)),
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
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Day header
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                if (canRemove)
                  IconButton(
                    onPressed: onRemoveDay,
                    icon: Icon(Icons.remove_circle_outline,
                        size: 18, color: scheme.error),
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
                    style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 17),
                    decoration: InputDecoration(
                      hintText: 'اليوم ${dayIndex + 1} – مثال: صدر وترايسبس',
                      hintStyle: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant, fontSize: 15),
                      isDense: false,
                      border: InputBorder.none,
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withAlpha(0x1F),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${dayIndex + 1}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
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
                Expanded(child: _ColHeader('التمرين', flex: 1)),
              ],
            ),
          ),
          const Divider(height: 1),

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
                          ?.copyWith(color: scheme.primary)),
                  const SizedBox(width: 4),
                  Icon(Icons.add_circle_outline,
                      size: 16, color: scheme.primary),
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader(this.label, {required this.flex});
  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: theme.textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
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
    final scheme = Theme.of(context).colorScheme;

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
                        size: 16, color: scheme.onSurfaceVariant),
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

/// A modern wheel picker field for selecting numbers (sets/reps/rest).
///
/// - Shows current value in a compact box.
/// - On tap, opens a bottom sheet with a [CupertinoPicker] wheel.
/// - Keeps [TextEditingController] as the source of truth.
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
    final scheme = theme.colorScheme;

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
            color: scheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outline),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  suffix == null ? '$displayValue' : '$displayValue $suffix',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.unfold_more_rounded,
                  size: 18, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showWheel(BuildContext context) async {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final current = _currentValue();
    final initial = (current != null && values.contains(current))
        ? values.indexOf(current)
        : values.indexOf(hint).clamp(0, values.length - 1);

    int selectedIndex = initial;

    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: scheme.surface,
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
                        child: const Text('اختيار'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoTheme(
                    data: CupertinoThemeData(
                      brightness: theme.brightness,
                      primaryColor: scheme.primary,
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
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return TextField(
      controller: controller,
      onChanged: (_) => onChanged?.call(),
      textAlign: textAlign,
      keyboardType: TextInputType.text,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: theme.textTheme.bodyMedium
            ?.copyWith(color: scheme.onSurfaceVariant),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: scheme.outline),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────────────────────

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

// ─────────────────────────────────────────────────────────────────────────────
// Trainer plan card
// ─────────────────────────────────────────────────────────────────────────────

class _TrainerPlanCard extends StatelessWidget {
  const _TrainerPlanCard({required this.plan});
  final PlanItem plan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    Map<String, dynamic>? parsed;
    try {
      final raw = plan.content;
      if (raw.trim().startsWith('{')) {
        parsed = jsonDecode(raw) as Map<String, dynamic>?;
      }
    } catch (_) {}

    final title = parsed?['title'] as String? ?? '';
    final description = parsed?['description'] as String? ?? '';
    final days = (parsed?['days'] as List?) ?? const [];
    final exercises = (parsed?['exercises'] as List?)
            ?.map((e) => e.toString())
            .toList(growable: false) ??
        const <String>[];
    final durationDays = parsed?['durationDays'];
    final frequency = parsed?['frequency'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.secondary.withAlpha(0x66), width: 1.5),
        borderRadius: BorderRadius.circular(14),
        color: scheme.surface,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Text(
                  'من المدرب  •  ${plan.createdAt}',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(
                      color: scheme.secondary.withAlpha(0xCC)),
                ),
                const Spacer(),
                Text(
                  title.isNotEmpty ? title : 'خطة تدريبية',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                Icon(Icons.sports_outlined, color: scheme.secondary, size: 18),
              ],
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.right),
            ],
            if (days.isNotEmpty) ...[
              const SizedBox(height: 10),
              ...days.map(
                  (d) => _DaySummaryRow(dayJson: d as Map<String, dynamic>)),
            ],
            if (days.isEmpty && exercises.isNotEmpty) ...[
              const SizedBox(height: 10),
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
              const SizedBox(height: 8),
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
            if (title.isEmpty &&
                description.isEmpty &&
                days.isEmpty &&
                exercises.isEmpty) ...[
              const SizedBox(height: 8),
              Text(plan.content,
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.right),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My plan card – expandable day sections with full exercise detail
// ─────────────────────────────────────────────────────────────────────────────

class _MyPlanCard extends StatefulWidget {
  const _MyPlanCard({
    required this.plan,
    required this.theme,
    required this.onDelete,
  });
  final PlanItem plan;
  final ThemeData theme;
  final VoidCallback onDelete;

  @override
  State<_MyPlanCard> createState() => _MyPlanCardState();
}

class _MyPlanCardState extends State<_MyPlanCard> {
  // track which day indices are expanded; start all expanded
  late List<bool> _expanded;
  Map<String, dynamic>? _parsed;
  late String _title;
  late String _description;
  late List _days;
  bool _deleting = false;

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
    _expanded = List.filled(_days.length, true);
  }

  Future<void> _confirmDelete(BuildContext context) async {
    if (_deleting) return;

    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف الخطة'),
        content: const Text('هل أنت متأكد من حذف هذه الخطة نهائياً؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      widget.onDelete();
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final scheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: scheme.shadow.withAlpha(0x0F),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header bar ──────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withAlpha(0x59),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                // Delete button (fixed hit target)
                IconButton(
                  onPressed: _deleting ? null : () => _confirmDelete(context),
                  icon: _deleting
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.error,
                          ),
                        )
                      : Icon(Icons.delete_outline,
                          size: 22, color: scheme.error),
                  tooltip: 'حذف الخطة',
                  style: IconButton.styleFrom(
                    tapTargetSize: MaterialTapTargetSize.padded,
                    padding: const EdgeInsets.all(10),
                  ),
                ),
                const SizedBox(width: 6),
                // Date badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.surface.withAlpha(0x99),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    widget.plan.createdAt,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const Spacer(),
                // Title
                Flexible(
                  child: GestureDetector(
                    onLongPress: () => _confirmDelete(context),
                    child: Text(
                      _title.isNotEmpty ? _title : 'خطتي الشخصية',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.event_note_outlined,
                    size: 22, color: scheme.primary),
              ],
            ),
          ),

          // ── Description ─────────────────────────────────────
          if (_description.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                _description,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
                textAlign: TextAlign.right,
              ),
            ),

          // ── Day stat badges row ──────────────────────────────
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

          // ── Structured days ──────────────────────────────────
          if (_days.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...List.generate(_days.length, (i) {
              final dayJson = _days[i] as Map<String, dynamic>;
              return _ExpandableDaySection(
                dayJson: dayJson,
                dayIndex: i,
                isExpanded: _expanded[i],
                onToggle: () => setState(() => _expanded[i] = !_expanded[i]),
                theme: theme,
              );
            }),
            const SizedBox(height: 6),
          ] else ...[
            // Raw text fallback (old plans without JSON)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                widget.plan.content,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expandable day section
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandableDaySection extends StatelessWidget {
  const _ExpandableDaySection({
    required this.dayJson,
    required this.dayIndex,
    required this.isExpanded,
    required this.onToggle,
    required this.theme,
  });

  final Map<String, dynamic> dayJson;
  final int dayIndex;
  final bool isExpanded;
  final VoidCallback onToggle;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final dayName = (dayJson['day'] ?? 'اليوم ${dayIndex + 1}').toString();
    final exercises = (dayJson['exercises'] as List?) ?? const [];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(
          children: [
            // Day header – always visible, tap to expand/collapse
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Row(
                  children: [
                    // Expand chevron
                    AnimatedRotation(
                      turns: isExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: Icon(Icons.chevron_right,
                          size: 20, color: scheme.primary),
                    ),
                    const SizedBox(width: 6),
                    // Exercise count badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.primary.withAlpha(0x1F),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${exercises.length}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const Spacer(),
                    // Day name
                    Text(
                      dayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface,
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Day number circle
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Text(
                        '${dayIndex + 1}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Exercises list – shown when expanded
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: isExpanded
                  ? Column(
                      children: [
                        Divider(height: 1, color: scheme.outlineVariant),
                        ...exercises.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final ex = entry.value as Map<String, dynamic>;
                          return _ExerciseDetailRow(
                            ex: ex,
                            index: idx,
                            isLast: idx == exercises.length - 1,
                            theme: theme,
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

// ─────────────────────────────────────────────────────────────────────────────
// Exercise detail row – name + stats chips
// ─────────────────────────────────────────────────────────────────────────────

class _ExerciseDetailRow extends StatelessWidget {
  const _ExerciseDetailRow({
    required this.ex,
    required this.index,
    required this.isLast,
    required this.theme,
  });

  final Map<String, dynamic> ex;
  final int index;
  final bool isLast;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    final name = (ex['name'] ?? '').toString();
    final sets = ex['sets'];
    final reps = ex['reps'];
    final rest = ex['rest'];
    final notes = (ex['notes'] ?? '').toString();

    final hasAnyStats = sets != null || reps != null || rest != null;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Exercise name row
              Row(
                children: [
                  // Index circle
                  Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${index + 1}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    name,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
              // Stats chips row (always show a clear placeholder)
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (rest != null)
                    _StatBadge(
                      label: 'راحة',
                      value: '$rest ث',
                      icon: Icons.timer_outlined,
                      scheme: scheme,
                      theme: theme,
                    )
                  else
                    _StatBadge(
                      label: 'راحة',
                      value: '--',
                      icon: Icons.timer_outlined,
                      scheme: scheme,
                      theme: theme,
                    ),
                  const SizedBox(width: 6),
                  if (reps != null)
                    _StatBadge(
                      label: 'تكرار',
                      value: '$reps',
                      icon: Icons.repeat_outlined,
                      scheme: scheme,
                      theme: theme,
                    )
                  else
                    _StatBadge(
                      label: 'تكرار',
                      value: '--',
                      icon: Icons.repeat_outlined,
                      scheme: scheme,
                      theme: theme,
                    ),
                  const SizedBox(width: 6),
                  if (sets != null)
                    _StatBadge(
                      label: 'جولات',
                      value: '$sets',
                      icon: Icons.loop_outlined,
                      scheme: scheme,
                      theme: theme,
                    )
                  else
                    _StatBadge(
                      label: 'جولات',
                      value: '--',
                      icon: Icons.loop_outlined,
                      scheme: scheme,
                      theme: theme,
                    ),
                ],
              ),

              if (!hasAnyStats) ...[
                const SizedBox(height: 6),
                Text(
                  'ملاحظة: هذه الخطة لا تحتوي على جولات/تكرار/راحة. حرّر الخطة وأضف التفاصيل لنتائج أوضح.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                  textAlign: TextAlign.right,
                ),
              ],

              // Notes
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  notes,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
              color: scheme.outlineVariant),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat badge chip
// ─────────────────────────────────────────────────────────────────────────────

class _StatBadge extends StatelessWidget {
  const _StatBadge({
    required this.label,
    required this.value,
    required this.icon,
    required this.scheme,
    required this.theme,
  });

  final String label;
  final String value;
  final IconData icon;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withAlpha(0x66),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.primary.withAlpha(0x33)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 13, color: scheme.primary),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Day summary row – used only in _TrainerPlanCard (kept for trainer cards)
// ─────────────────────────────────────────────────────────────────────────────

class _DaySummaryRow extends StatelessWidget {
  const _DaySummaryRow({required this.dayJson});
  final Map<String, dynamic> dayJson;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dayName = (dayJson['day'] ?? '').toString();
    final exercises = (dayJson['exercises'] as List?) ?? const [];

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Day name bar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              dayName,
              textAlign: TextAlign.right,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 6),
          ...exercises.map((e) {
            final ex = e as Map<String, dynamic>;
            final name = (ex['name'] ?? '').toString();
            final sets = ex['sets'];
            final reps = ex['reps'];
            final rest = ex['rest'];
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    name,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (sets != null || reps != null || rest != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (rest != null) ...[
                          _MiniChip(label: '$rest ث راحة', scheme: scheme),
                          const SizedBox(width: 4),
                        ],
                        if (reps != null) ...[
                          _MiniChip(label: '$reps تكرار', scheme: scheme),
                          const SizedBox(width: 4),
                        ],
                        if (sets != null)
                          _MiniChip(label: '$sets جولات', scheme: scheme),
                      ],
                    ),
                  ],
                ],
              ),
            );
          }),
          const Divider(height: 14),
        ],
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.label, required this.scheme});
  final String label;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
            fontSize: 11,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _InfoTag extends StatelessWidget {
  const _InfoTag({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: scheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
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
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 40),
        Icon(Icons.error_outline, size: 40, color: scheme.onSurfaceVariant),
        const SizedBox(height: 12),
        Text(title,
            textAlign: TextAlign.center,
            style: TextStyle(color: scheme.onSurfaceVariant)),
        const SizedBox(height: 16),
        Center(
          child: OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('إعادة المحاولة'),
          ),
        ),
      ],
    );
  }
}
