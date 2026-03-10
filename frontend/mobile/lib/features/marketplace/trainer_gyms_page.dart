import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import 'marketplace_api_service.dart';
import 'marketplace_models.dart';

class TrainerGymsPage extends StatefulWidget {
  const TrainerGymsPage({super.key, required this.session});

  final AuthSession? session;

  @override
  State<TrainerGymsPage> createState() => _TrainerGymsPageState();
}

class _TrainerGymsPageState extends State<TrainerGymsPage> {
  late final MarketplaceApiService _api;
  late Future<_TrainerGymsData> _dataFuture;
  final TextEditingController _searchController = TextEditingController();

  String? _selectedCity;
  static const List<String> _cityOptions = <String>[
    'بغداد',
    'البصرة',
    'أربيل',
    'النجف',
    'كربلاء',
    'الموصل',
    'السليمانية',
    'ديالى',
    'ذي قار',
    'واسط',
    'صلاح الدين',
    'الأنبار',
    'بابل',
    'كركوك',
    'ميسان',
    'المثنى',
    'القادسية',
  ];

  List<GymSummary> _searchResults = [];
  bool _isSearching = false;
  String? _searchError;

  @override
  void initState() {
    super.initState();
    _api =
        MarketplaceApiService(role: AppRole.trainer, session: widget.session);
    _dataFuture = _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
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
              Text('شبكة النوادي',
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: AppTheme.cardLime)),
              const SizedBox(height: 8),
              Text(
                'يمكنك الانضمام إلى 4 نوادٍ كحد أقصى.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 16),

              // Search Section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: AppTheme.cardLavender.withValues(alpha: 0.08),
                  border: Border.all(
                      color: AppTheme.cardLavender.withValues(alpha: 0.15)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('البحث عن نادي',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(color: AppTheme.cardLavender)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: 'اسم النادي',
                        hintText: 'مثال: GymOS، نادي القوة، فتنس...',
                        prefixIcon: const Icon(Icons.fitness_center),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search),
                          onPressed: _searchGyms,
                        ),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      onSubmitted: (_) => _searchGyms(),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCity,
                      decoration: InputDecoration(
                        labelText: 'المدينة (فلتر)',
                        prefixIcon: const Icon(Icons.location_city),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('كل المدن'),
                        ),
                        ..._cityOptions.map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(c),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _selectedCity = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _searchGyms,
                            icon: const Icon(Icons.search),
                            label: const Text('بحث'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton(
                          onPressed: _loadAllGyms,
                          child: const Text('عرض الكل'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Search Results
              if (_isSearching)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_searchError != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(_searchError!,
                      style: TextStyle(color: Colors.red.shade700)),
                )
              else if (_searchResults.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('نتائج البحث (${_searchResults.length})',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                ..._searchResults.map((gym) => _GymSearchResultCard(
                      gym: gym,
                      onJoin: () => _joinGym(gym),
                      isAlreadyJoined: data.gyms.any((g) => g.gymId == gym.id),
                    )),
              ],

              const SizedBox(height: 24),
              Text('نواديك الحالية (${data.gyms.length}/4)',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(color: AppTheme.cardLime)),
              const SizedBox(height: 8),
              if (data.gyms.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: AppTheme.textSecondary.withValues(alpha: 0.1),
                  ),
                  child: const Text(
                      'أنت غير منضم لأي نادي حالياً. ابحث عن نادي للانضمام.'),
                ),
              ...data.gyms.map(
                (gym) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppTheme.cardLime,
                      child: Icon(Icons.fitness_center, color: Colors.black),
                    ),
                    title: Text(gym.gymName),
                    subtitle: Text('المدينة: ${gym.city} | عملاء نشطون: ${gym.activeClients}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${gym.averageRating.toStringAsFixed(1)} ⭐'),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: 'إلغاء الانظمام',
                          onPressed: () => _leaveGym(gym),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('العملاء النشطون', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              if (data.clients.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: AppTheme.textSecondary.withValues(alpha: 0.1),
                  ),
                  child: const Text('لا يوجد عملاء نشطون حالياً.'),
                ),
              ...data.clients.map(
                (client) => Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(client.name),
                    subtitle: Text('المعرف: ${client.id}'),
                  ),
                ),
              ),
              const SizedBox(height: 80),
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

  Future<void> _searchGyms() async {
    final name = _searchController.text.trim();
    final city = _selectedCity;

    setState(() {
      _isSearching = true;
      _searchError = null;
    });

    try {
      final results = await _api.fetchPublicGyms(
        name: name.isEmpty ? null : name,
        city: city,
      );
      setState(() {
        _searchResults = results;
        _isSearching = false;
        if (results.isEmpty) {
          final hasAnyFilter =
              name.isNotEmpty || (city != null && city.isNotEmpty);
          if (!hasAnyFilter) {
            _searchError = 'لا توجد نوادي مسجلة حالياً';
          } else if (name.isNotEmpty && city != null && city.isNotEmpty) {
            _searchError = 'لا توجد نتائج لـ "$name" في "$city"';
          } else if (name.isNotEmpty) {
            _searchError = 'لا توجد نتائج لـ "$name"';
          } else {
            _searchError = 'لا توجد نوادي في "$city"';
          }
        }
      });
    } catch (e) {
      setState(() {
        _isSearching = false;
        _searchError = 'تعذر البحث: $e';
      });
    }
  }

  Future<void> _loadAllGyms() async {
    _searchController.clear();
    setState(() {
      _selectedCity = null;
    });
    await _searchGyms();
  }

  Future<void> _joinGym(GymSummary gym) async {
    // Check if already at max (4 gyms)
    final currentData = await _dataFuture;
    if (!mounted) return;
    if (currentData.gyms.length >= 4) {
      _showMessage('لا يمكنك الانضمام لأكثر من 4 نوادٍ');
      return;
    }

    // Confirm join
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الانضمام'),
        content:
            Text('هل تريد الانضمام إلى "${gym.name}" في ${gym.city} كمدرب؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('انضمام'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.joinGymAsTrainer(gym.id);
      if (!mounted) return;
      _showMessage('تم الانضمام للنادي بنجاح');
      _reload();
    } catch (e) {
      if (!mounted) return;
      _showMessage('تعذر الانضمام: $e');
    }
  }

  Future<void> _leaveGym(TrainerGymItem gym) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الانضمام'),
        content: Text('هل تريد إلغاء الانضمام إلى "${gym.gymName}"؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await _api.leaveGymAsTrainer(gym.gymId);
      if (!mounted) return;
      _showMessage('تم إلغاء الانضمام بنجاح');
      _reload();
    } catch (e) {
      if (!mounted) return;
      _showMessage('تعذر إلغاء الانضمام: $e');
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
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GymSearchResultCard extends StatelessWidget {
  const _GymSearchResultCard({
    required this.gym,
    required this.onJoin,
    required this.isAlreadyJoined,
  });

  final GymSummary gym;
  final VoidCallback onJoin;
  final bool isAlreadyJoined;

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
                const CircleAvatar(
                  backgroundColor: AppTheme.cardLavender,
                  child: Icon(Icons.fitness_center, color: Colors.black),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(gym.name,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(gym.city,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Text('${gym.averageRating.toStringAsFixed(1)} ⭐'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _InfoChip(
                    icon: Icons.people, label: '${gym.membersCount} أعضاء'),
                const SizedBox(width: 8),
                _InfoChip(
                    icon: Icons.sports, label: '${gym.trainersCount} مدربين'),
                const Spacer(),
                if (isAlreadyJoined)
                  Chip(
                    label: const Text('منضم'),
                    backgroundColor: AppTheme.cardLime.withValues(alpha: 0.3),
                  )
                else
                  FilledButton.icon(
                    onPressed: onJoin,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('انضمام'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

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
