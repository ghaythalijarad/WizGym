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
  final TextEditingController _planController = TextEditingController();
  bool _isSubmitting = false;
  String? _selectedTraineeId;

  @override
  void initState() {
    super.initState();
    _api = PlansApiService(role: AppRole.trainer, session: widget.session);
    _dataFuture = _loadData();
  }

  @override
  void dispose() {
    _planController.dispose();
    super.dispose();
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

          if (snapshot.hasError) {
            return _ErrorState(onRetry: _reload);
          }

          final data =
              snapshot.data ?? const _TrainerPlansData(clients: [], plans: []);
          final clients = data.clients;
          final hasClients = clients.isNotEmpty;

          if (_selectedTraineeId != null &&
              !clients.any((item) => item.id == _selectedTraineeId)) {
            _selectedTraineeId = null;
          }

          _selectedTraineeId ??= hasClients ? clients.first.id : null;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
                16, 16, 16, 16 + MediaQuery.paddingOf(context).bottom + 80),
            children: [
              Text('خطط التدريب',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(color: AppTheme.cardLime)),
              const SizedBox(height: 8),
              Text(
                'اكتب خطة نصية وأرسلها إلى أحد متدربيك النشطين.',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 12),
              if (!hasClients)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                        'لا يوجد لديك متدربون نشطون حالياً. يمكنك كتابة الخطة الآن وسيتم تفعيل الإرسال عند وجود متدرب نشط.'),
                  ),
                ),
              DropdownButtonFormField<String>(
                initialValue: _selectedTraineeId,
                decoration: const InputDecoration(labelText: 'اختر المتدرب'),
                items: hasClients
                    ? clients
                        .map(
                          (item) => DropdownMenuItem<String>(
                            value: item.id,
                            child: Text('${item.name} (${item.gymId})'),
                          ),
                        )
                        .toList(growable: false)
                    : const [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text('لا يوجد متدربون نشطون'),
                        ),
                      ],
                onChanged: hasClients
                    ? (value) {
                        setState(() {
                          _selectedTraineeId = value;
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _planController,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(
                  labelText: 'الخطة النصية',
                  hintText:
                      'مثال: يوم الاثنين ظهر + باي، 45 دقيقة كارديو خفيف...',
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 46,
                child: FilledButton.icon(
                  onPressed: (!hasClients || _isSubmitting) ? null : _sendPlan,
                  icon: _isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_outlined),
                  label: const Text('إرسال الخطة'),
                ),
              ),
              const SizedBox(height: 16),
              Text('الخطط المرسلة', style: theme.textTheme.titleLarge),
              const SizedBox(height: 8),
              if (data.plans.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('لم ترسل أي خطة بعد.'),
                  ),
                ),
              ...data.plans.map(
                (plan) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'إلى: ${plan.traineeName}',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            Text(plan.createdAt,
                                style: theme.textTheme.bodySmall),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(plan.content, style: theme.textTheme.bodyMedium),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<_TrainerPlansData> _loadData() async {
    final clientsFuture = _api.fetchTrainerClients();
    final plansFuture = _api.fetchMyPlans();

    final clients = await clientsFuture;
    final plans = await plansFuture;

    return _TrainerPlansData(
      clients: clients,
      plans: plans
          .where((item) => item.type == 'TRAINER_TO_TRAINEE')
          .toList(growable: false),
    );
  }

  Future<void> _sendPlan() async {
    final traineeUserId = _selectedTraineeId;
    final content = _planController.text.trim();

    if (traineeUserId == null || traineeUserId.isEmpty) {
      _showMessage('اختر المتدرب أولاً');
      return;
    }

    if (content.length < 3) {
      _showMessage('اكتب خطة لا تقل عن 3 أحرف');
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _api.sendTrainerPlan(
        traineeUserId: traineeUserId,
        content: content,
      );
      _planController.clear();
      _showMessage('تم إرسال الخطة للمتدرب');
      _reload();
    } catch (_) {
      _showMessage('تعذر إرسال الخطة (تأكد من أن المتدرب نشط لديك)');
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _dataFuture = _loadData();
    });
    await _dataFuture;
  }

  void _reload() {
    setState(() {
      _dataFuture = _loadData();
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TrainerPlansData {
  const _TrainerPlansData({
    required this.clients,
    required this.plans,
  });

  final List<TrainerClientSummary> clients;
  final List<PlanItem> plans;
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
        const Icon(Icons.error_outline, size: 42, color: AppTheme.cardPink),
        const SizedBox(height: 10),
        const Text('تعذر تحميل خطط المدرب',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textPrimary)),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
