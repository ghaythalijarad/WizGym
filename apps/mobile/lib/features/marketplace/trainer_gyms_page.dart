import 'package:flutter/material.dart';

import '../../core/models/app_role.dart';
import 'marketplace_api_service.dart';
import 'marketplace_models.dart';

class TrainerGymsPage extends StatefulWidget {
  const TrainerGymsPage({super.key});

  @override
  State<TrainerGymsPage> createState() => _TrainerGymsPageState();
}

class _TrainerGymsPageState extends State<TrainerGymsPage> {
  late final MarketplaceApiService _api;
  late Future<_TrainerGymsData> _dataFuture;
  final TextEditingController _gymIdController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.trainer);
    _dataFuture = _loadData();
  }

  @override
  void dispose() {
    _gymIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<_TrainerGymsData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(onRetry: _reload);
          }

          final data = snapshot.data ?? const _TrainerGymsData(gyms: [], clients: []);

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('شبكة النوادي', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'يمكنك الانضمام إلى 4 نوادٍ كحد أقصى.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _gymIdController,
                decoration: const InputDecoration(
                  labelText: 'أدخل Gym ID للانضمام',
                  hintText: 'مثال: gym-2001',
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: _joinGym,
                child: const Text('انضمام كنادي مدرب'),
              ),
              const SizedBox(height: 18),
              Text('نواديك الحالية (${data.gyms.length}/4)', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (data.gyms.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('أنت غير منضم لأي نادي حالياً.'),
                  ),
                ),
              ...data.gyms.map(
                (gym) => Card(
                  child: ListTile(
                    title: Text(gym.gymName),
                    subtitle: Text('المدينة: ${gym.city} | عملاء نشطون: ${gym.activeClients}'),
                    trailing: Text('${gym.averageRating.toStringAsFixed(1)} ⭐'),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('العملاء النشطون', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (data.clients.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(14),
                    child: Text('لا يوجد عملاء نشطون حالياً.'),
                  ),
                ),
              ...data.clients.map(
                (client) => Card(
                  child: ListTile(
                    title: Text(client.name),
                    subtitle: Text('المعرف: ${client.id} | النادي: ${client.gymId}'),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<_TrainerGymsData> _loadData() async {
    final gyms = await _api.fetchTrainerGyms();
    final clients = await _api.fetchTrainerClients();
    return _TrainerGymsData(gyms: gyms, clients: clients);
  }

  Future<void> _joinGym() async {
    final gymId = _gymIdController.text.trim();
    if (gymId.isEmpty) {
      _showMessage('أدخل Gym ID أولاً');
      return;
    }

    try {
      await _api.joinGymAsTrainer(gymId);
      _showMessage('تم الانضمام للنادي بنجاح');
      _gymIdController.clear();
      _reload();
    } catch (_) {
      _showMessage('تعذر الانضمام (تأكد من حد 4 نوادٍ أو Gym ID)');
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

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _TrainerGymsData {
  const _TrainerGymsData({required this.gyms, required this.clients});

  final List<TrainerGymItem> gyms;
  final List<TrainerClientItem> clients;
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
        Icon(Icons.error_outline, size: 42, color: Colors.red.shade700),
        const SizedBox(height: 10),
        const Text('تعذر تحميل بيانات المدرب', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
