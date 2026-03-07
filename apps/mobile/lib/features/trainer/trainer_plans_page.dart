import 'dart:convert';
import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../plans/plans_api_service.dart';

class TrainerPlansPage extends StatefulWidget {
  const TrainerPlansPage({super.key});

  @override
  State<TrainerPlansPage> createState() => _TrainerPlansPageState();
}

class _TrainerPlansPageState extends State<TrainerPlansPage> {
  final AuthSessionStore _sessionStore = AuthSessionStore();

  AuthSession? _session;
  late Future<List<TrainerClientSummary>> _clientsFuture;

  final TextEditingController _planTitleController = TextEditingController();
  final TextEditingController _planDescriptionController =
      TextEditingController();
  final TextEditingController _exercisesController = TextEditingController();
  final TextEditingController _durationController = TextEditingController();
  final TextEditingController _frequencyController = TextEditingController();

  String? _selectedClientId;
  String? _selectedClientName;
  bool _isLoading = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _clientsFuture = _loadClients();
  }

  @override
  void dispose() {
    _planTitleController.dispose();
    _planDescriptionController.dispose();
    _exercisesController.dispose();
    _durationController.dispose();
    _frequencyController.dispose();
    super.dispose();
  }

  Future<PlansApiService> _api() async {
    _session ??= await _sessionStore.load();
    return PlansApiService(role: AppRole.trainer, session: _session);
  }

  Future<List<TrainerClientSummary>> _loadClients() async {
    final api = await _api();
    return api.fetchTrainerClients();
  }

  Future<void> _refresh() async {
    setState(() {
      _clientsFuture = _loadClients();
    });
  }

  String _buildPlanContent() {
    final title = _planTitleController.text.trim();
    final description = _planDescriptionController.text.trim();
    final exercises = _exercisesController.text
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    final durationRaw = _durationController.text.trim();
    final duration = durationRaw.isEmpty ? null : int.tryParse(durationRaw);
    final frequency = _frequencyController.text.trim().isEmpty
        ? null
        : _frequencyController.text.trim();

    final payload = <String, dynamic>{
      'title': title,
      if (description.isNotEmpty) 'description': description,
      if (exercises.isNotEmpty) 'exercises': exercises,
      if (duration != null) 'durationDays': duration,
      if (frequency != null) 'frequency': frequency,
    };

    return jsonEncode(payload);
  }

  Future<void> _sendPlan() async {
    if (_selectedClientId == null || _selectedClientId!.isEmpty) {
      setState(() => _error = 'يرجى اختيار متدرب');
      return;
    }
    if (_planTitleController.text.trim().isEmpty) {
      setState(() => _error = 'يرجى إدخال عنوان الخطة');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    try {
      final api = await _api();
      await api.sendTrainerPlan(
        traineeUserId: _selectedClientId!,
        content: _buildPlanContent(),
      );

      setState(() {
        _success = 'تم إرسال الخطة إلى $_selectedClientName بنجاح';
        _isLoading = false;
        _planTitleController.clear();
        _planDescriptionController.clear();
        _exercisesController.clear();
        _durationController.clear();
        _frequencyController.clear();
        _selectedClientId = null;
        _selectedClientName = null;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('إرسال خطة تدريبية'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: FutureBuilder<List<TrainerClientSummary>>(
        future: _clientsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(Icons.error_outline, size: 56, color: scheme.error),
                  const SizedBox(height: 12),
                  Text(
                    'تعذر تحميل المتدربين',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    snapshot.error.toString(),
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: _refresh, child: const Text('إعادة المحاولة')),
                ],
              ),
            );
          }

          final clients = snapshot.data ?? const <TrainerClientSummary>[];

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('اختر المتدرب',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _selectedClientId,
                  items: clients
                      .map((client) => DropdownMenuItem(
                            value: client.id,
                            child: Text('${client.name} (${client.gymId})'),
                          ))
                      .toList(),
                  onChanged: (value) {
                    if (value == null) return;
                    final client = clients.firstWhere((c) => c.id == value);
                    setState(() {
                      _selectedClientId = value;
                      _selectedClientName = client.name;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'المتدرب'),
                ),
                const SizedBox(height: 18),
                Text('تفاصيل الخطة',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 12),
                TextField(
                  controller: _planTitleController,
                  decoration: const InputDecoration(
                    labelText: 'عنوان الخطة (مثال: تضخيم العضلات 8 أسابيع)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _planDescriptionController,
                  maxLines: 3,
                  decoration:
                      const InputDecoration(labelText: 'وصف الخطة (اختياري)'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _exercisesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'التمارين (مفصولة بفواصل)',
                    hintText: 'مثال: تمرين الضغط، سحب الأرضية، القرفصاء',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'المدة (أيام)'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _frequencyController,
                        decoration: const InputDecoration(
                          labelText: 'التكرار (مثال: 3 مرات/أسبوع)',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    onPressed: _isLoading ? null : _sendPlan,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('إرسال الخطة'),
                  ),
                ),
                if (_success != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: scheme.primary.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _success!,
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: scheme.error.withValues(alpha: 0.5)),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
