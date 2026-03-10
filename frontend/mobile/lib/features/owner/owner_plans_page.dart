import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
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
      _showMsg('تمت إضافة خطة الاشتراك');
      _reloadPlans();
    } catch (e) {
      _showMsg('تعذرت الإضافة: $e');
    }
  }

  Future<void> _deletePlan(GymSubscriptionPlan plan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('حذف خطة الاشتراك'),
        content: Text('هل تريد حذف "${plan.title}"؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
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
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(() => _gymsFuture = _api.fetchOwnerGyms());
        await _gymsFuture;
        _reloadPlans();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          Text('خطط اشتراك النادي',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          Text(
              'أنشئ خطط أسعار (شهري، ٣ أشهر، سنوي…) ليراها المتدربون عند الانضمام.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),

          // gym selector
          FutureBuilder<List<GymSummary>>(
            future: _gymsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const LinearProgressIndicator();
              }
              final gyms = snap.data ?? [];
              if (gyms.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('لا توجد نوادي. أنشئ نادي أولاً.'),
                  ),
                );
              }
              _selectedGymId ??= gyms.first.id;

              // Trigger initial plans load when the tab is opened.
              if (!_initialLoadDone) {
                _initialLoadDone = true;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  if (_selectedGymId != null) {
                    setState(() {
                      _plansFuture = _api.fetchSubscriptionPlans(_selectedGymId!);
                    });
                  }
                });
              }

              return DropdownButtonFormField<String>(
                initialValue: _selectedGymId,
                decoration: const InputDecoration(labelText: 'اختر النادي'),
                items: gyms
                    .map((g) => DropdownMenuItem(
                        value: g.id, child: Text('${g.name} (${g.city})')))
                    .toList(growable: false),
                onChanged: (v) {
                  if (v != null) _onGymSelected(v);
                },
              );
            },
          ),
          const SizedBox(height: 14),

          // add plan form
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('إضافة خطة جديدة',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                        labelText: 'اسم الخطة', hintText: 'مثال: اشتراك شهري'),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _durationMonths,
                          decoration:
                              const InputDecoration(labelText: 'المدة (شهر)'),
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
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _priceController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'السعر', suffixText: 'د.ع'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descController,
                    decoration:
                        const InputDecoration(labelText: 'وصف (اختياري)'),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton.icon(
                    onPressed: _addPlan,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('إضافة الخطة'),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // existing plans
          Text('الخطط الحالية', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          FutureBuilder<List<GymSubscriptionPlan>>(
            future: _plansFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(
                    child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(),
                ));
              }
              final plans = snap.data ?? [];
              if (plans.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child:
                        Text('لا توجد خطط اشتراك حتى الآن. أضف واحدة أعلاه.'),
                  ),
                );
              }
              return Column(
                children: plans.map((p) => _buildPlanTile(p)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlanTile(GymSubscriptionPlan plan) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text('${plan.durationMonths}',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        title: Text(plan.title),
        subtitle: Text(
          '${plan.durationMonths} ${plan.durationMonths == 1 ? 'شهر' : 'أشهر'} — ${plan.price} ${plan.currency}',
        ),
        trailing: IconButton(
          onPressed: () => _deletePlan(plan),
          icon: const Icon(Icons.delete_outline, color: Colors.red),
        ),
      ),
    );
  }
}
