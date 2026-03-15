import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';

class OwnerPlansPage extends StatefulWidget {
  const OwnerPlansPage({super.key, this.session});

  final AuthSession? session;

  @override
  State<OwnerPlansPage> createState() => _OwnerPlansPageState();
}

class _OwnerPlansPageState extends State<OwnerPlansPage> {
  late final MarketplaceApiService _api;
  late Future<List<GymSummary>> _gymsFuture;
  String? _selectedGymId;

  late Future<List<GymSubscriptionPlan>> _plansFuture;

  final _titleController = TextEditingController();
  final _priceController = TextEditingController();
  final _descController = TextEditingController();
  int _durationMonths = 1;
  bool _initialLoadDone = false;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
    _gymsFuture = _api.fetchOwnerGyms();
    _plansFuture = Future.value(const []);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _priceController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _onGymSelected(String gymId) {
    setState(() {
      _selectedGymId = gymId;
      _plansFuture = _api.fetchSubscriptionPlans(gymId);
    });
  }

  void _reloadPlans() {
    if (_selectedGymId == null) return;
    setState(() {
      _plansFuture = _api.fetchSubscriptionPlans(_selectedGymId!);
    });
  }

  Future<void> _addPlan() async {
    final gymId = _selectedGymId;
    if (gymId == null) {
      _showMsg('اختر النادي أولاً');
      return;
    }
    final title = _titleController.text.trim();
    final price = int.tryParse(_priceController.text.trim());
    if (title.isEmpty || price == null || price <= 0) {
      _showMsg('يرجى ملء اسم الخطة والسعر');
      return;
    }
    setState(() => _adding = true);
    try {
      await _api.createSubscriptionPlan(
        gymId: gymId,
        title: title,
        durationMonths: _durationMonths,
        price: price,
        description: _descController.text,
      );
      _titleController.clear();
      _priceController.clear();
      _descController.clear();
      setState(() => _durationMonths = 1);
      _showMsg('✓ تمت إضافة خطة الاشتراك');
      _reloadPlans();
    } catch (e) {
      _showMsg('تعذرت الإضافة: $e');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _deletePlan(GymSubscriptionPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E35),
        title: const Text('حذف الخطة',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('هل تريد حذف "${plan.title}"؟',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textSecondary))),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('حذف')),
        ],
      ),
    );
    if (confirmed != true || _selectedGymId == null) return;
    try {
      await _api.deleteSubscriptionPlan(
        gymId: _selectedGymId!,
        planId: plan.planId,
      );
      _showMsg('تم حذف الخطة');
      _reloadPlans();
    } catch (_) {
      _showMsg('تعذر الحذف');
    }
  }

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF1E1E35),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppTheme.gold,
      backgroundColor: const Color(0xFF1E1E35),
      onRefresh: () async {
        setState(() => _gymsFuture = _api.fetchOwnerGyms());
        await _gymsFuture;
        _reloadPlans();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // ── Page header ────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'خطط الاشتراك',
                style: TextStyle(
                  color: AppTheme.gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Gym selector ───────────────────────────────────────────
          FutureBuilder<List<GymSummary>>(
            future: _gymsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(color: AppTheme.gold),
                );
              }
              final gyms = snap.data ?? [];
              if (gyms.isEmpty) {
                return const _EmptyCard(
                  icon: Icons.sports_gymnastics_rounded,
                  text: 'لا توجد نوادي. أنشئ نادياً أولاً.',
                );
              }
              _selectedGymId ??= gyms.first.id;
              if (!_initialLoadDone) {
                _initialLoadDone = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (_selectedGymId != null) {
                    setState(() {
                      _plansFuture =
                          _api.fetchSubscriptionPlans(_selectedGymId!);
                    });
                  }
                });
              }

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF16162A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedGymId,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E1E35),
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14),
                    iconEnabledColor: AppTheme.gold,
                    items: gyms
                        .map((g) => DropdownMenuItem(
                            value: g.id,
                            child: Text('${g.name} — ${g.city}',
                                style: const TextStyle(
                                    color: AppTheme.textPrimary))))
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) _onGymSelected(v);
                    },
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Add plan form ──────────────────────────────────────────
          const _SectionLabel(
              label: 'إضافة خطة جديدة', icon: Icons.add_circle_outline_rounded),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF16162A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(
                  color: AppTheme.gold.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _GoldTextField(
                  controller: _titleController,
                  label: 'اسم الخطة',
                  hint: 'مثال: اشتراك شهري',
                  icon: Icons.label_outline_rounded,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _GoldDropdown(
                        value: _durationMonths,
                        label: 'المدة',
                        icon: Icons.timer_outlined,
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 شهر')),
                          DropdownMenuItem(value: 2, child: Text('2 أشهر')),
                          DropdownMenuItem(value: 3, child: Text('3 أشهر')),
                          DropdownMenuItem(value: 6, child: Text('6 أشهر')),
                          DropdownMenuItem(value: 12, child: Text('12 شهر')),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _durationMonths = v);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _GoldTextField(
                        controller: _priceController,
                        label: 'السعر',
                        hint: '0',
                        icon: Icons.payments_outlined,
                        suffix: 'د.ع',
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _GoldTextField(
                  controller: _descController,
                  label: 'وصف (اختياري)',
                  hint: 'تفاصيل إضافية...',
                  icon: Icons.notes_rounded,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _adding ? null : _addPlan,
                    icon: _adding
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: AppTheme.textOnGold),
                          )
                        : const Icon(Icons.add_rounded, size: 18),
                    label: Text(_adding ? 'جارٍ الإضافة...' : 'إضافة الخطة'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.gold,
                      foregroundColor: AppTheme.textOnGold,
                      disabledBackgroundColor: AppTheme.gold.withValues(alpha: 0.4),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ── Existing plans ─────────────────────────────────────────
          const _SectionLabel(
              label: 'الخطط الحالية', icon: Icons.list_alt_rounded),
          const SizedBox(height: 10),
          FutureBuilder<List<GymSubscriptionPlan>>(
            future: _plansFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(color: AppTheme.gold),
                  ),
                );
              }
              final plans = snap.data ?? [];
              if (plans.isEmpty) {
                return const _EmptyCard(
                  icon: Icons.assignment_late_outlined,
                  text: 'لا توجد خطط اشتراك حتى الآن. أضف واحدة أعلاه.',
                );
              }
              return Column(
                children: plans
                    .map((p) => _PlanTile(
                          plan: p,
                          onDelete: () => _deletePlan(p),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.gold),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(
            color: AppTheme.gold,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.gold.withValues(alpha: 0.5), size: 30),
          const SizedBox(width: 14),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _GoldTextField extends StatelessWidget {
  const _GoldTextField({
    required this.controller,
    required this.label,
    required this.hint,
    required this.icon,
    this.suffix,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final IconData icon;
  final String? suffix;
  final TextInputType? keyboardType;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: AppTheme.textPrimary),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        prefixIcon: Icon(icon, color: AppTheme.gold, size: 18),
        labelStyle: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
        hintStyle: const TextStyle(color: AppTheme.textMuted),
        suffixStyle: const TextStyle(color: AppTheme.textMuted),
        filled: true,
        fillColor: const Color(0xFF1E1E35),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.gold.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppTheme.gold.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppTheme.gold, width: 1.5),
        ),
      ),
    );
  }
}

class _GoldDropdown extends StatelessWidget {
  const _GoldDropdown({
    required this.value,
    required this.label,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  final int value;
  final String label;
  final IconData icon;
  final List<DropdownMenuItem<int>> items;
  final void Function(int?) onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E35),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.2)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppTheme.gold),
              const SizedBox(width: 4),
              Text(label,
                  style:
                      const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ],
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isExpanded: true,
              dropdownColor: const Color(0xFF1E1E35),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
              iconEnabledColor: AppTheme.gold,
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({required this.plan, required this.onDelete});
  final GymSubscriptionPlan plan;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final months = plan.durationMonths;
    final durationLabel = '$months ${months == 1 ? 'شهر' : 'أشهر'}';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            // Duration badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppTheme.gold, AppTheme.goldDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  '$months',
                  style: const TextStyle(
                    color: AppTheme.textOnGold,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan.title,
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _MiniChip(
                          icon: Icons.timer_outlined,
                          label: durationLabel,
                          color: AppTheme.gold),
                      const SizedBox(width: 6),
                      _MiniChip(
                          icon: Icons.payments_outlined,
                          label: '${plan.price} ${plan.currency}',
                          color: const Color(0xFF34D399)),
                    ],
                  ),
                  if (plan.description != null &&
                      plan.description!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      plan.description!,
                      style: const TextStyle(
                          color: AppTheme.textMuted, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: Colors.redAccent.withValues(alpha: 0.8),
              tooltip: 'حذف',
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
