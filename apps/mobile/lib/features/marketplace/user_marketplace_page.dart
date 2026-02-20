import 'package:flutter/material.dart';

import '../../core/models/app_role.dart';
import 'marketplace_api_service.dart';
import 'marketplace_models.dart';
import 'user_marketplace_detail_page.dart';

class UserMarketplacePage extends StatefulWidget {
  const UserMarketplacePage({super.key});

  @override
  State<UserMarketplacePage> createState() => _UserMarketplacePageState();
}

class _UserMarketplacePageState extends State<UserMarketplacePage> {
  late final MarketplaceApiService _api;
  late Future<List<GymSummary>> _gymsFuture;
  final TextEditingController _cityController = TextEditingController();
  String _audienceFilter = '';

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.user);
    _gymsFuture = _api.fetchPublicGyms();
  }

  @override
  void dispose() {
    _cityController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<GymSummary>>(
        future: _gymsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(
              message: 'تعذر تحميل قائمة النوادي',
              onRetry: _reload,
            );
          }

          final gyms = snapshot.data ?? const <GymSummary>[];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('استكشف النوادي', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'انضم إلى النادي المناسب، ثم شاهد المدربين وابدأ التدريب.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cityController,
                decoration: InputDecoration(
                  labelText: 'تصفية حسب المدينة',
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.search),
                    onPressed: _filterByCity,
                  ),
                ),
                onSubmitted: (_) => _filterByCity(),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _audienceFilter,
                decoration: const InputDecoration(labelText: 'الفئة'),
                items: const [
                  DropdownMenuItem(value: '', child: Text('الكل')),
                  DropdownMenuItem(value: 'MEN_ONLY', child: Text('رجال فقط')),
                  DropdownMenuItem(value: 'WOMEN_ONLY', child: Text('نساء فقط')),
                  DropdownMenuItem(value: 'MIXED', child: Text('رجال ونساء')),
                ],
                onChanged: (value) {
                  setState(() {
                    _audienceFilter = value ?? '';
                    _gymsFuture = _api.fetchPublicGyms(
                      city: _cityController.text,
                      audience: _audienceFilter,
                    );
                  });
                },
              ),
              const SizedBox(height: 14),
              if (gyms.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('لا توجد نوادي متاحة حالياً.'),
                  ),
                ),
              ...gyms.map((gym) => _buildGymCard(context, gym)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGymCard(BuildContext context, GymSummary gym) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: SizedBox(
                height: 132,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: gym.coverImageUrl == null || gym.coverImageUrl!.isEmpty
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [
                                    scheme.primary.withValues(alpha: 0.14),
                                    scheme.secondary.withValues(alpha: 0.10),
                                    scheme.tertiary.withValues(alpha: 0.10),
                                  ],
                                ),
                              ),
                              child: const Icon(Icons.fitness_center_rounded, size: 42),
                            )
                          : Image.network(
                              gym.coverImageUrl!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topRight,
                                    end: Alignment.bottomLeft,
                                    colors: [
                                      scheme.primary.withValues(alpha: 0.14),
                                      scheme.secondary.withValues(alpha: 0.10),
                                      scheme.tertiary.withValues(alpha: 0.10),
                                    ],
                                  ),
                                ),
                                child: const Icon(Icons.image_not_supported_outlined, size: 36),
                              ),
                            ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.55),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      bottom: 10,
                      right: 12,
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              gym.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          _Badge(label: '${gym.averageRating.toStringAsFixed(1)} ★'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoPill(icon: Icons.location_on_outlined, text: gym.city),
                _InfoPill(icon: Icons.groups_outlined, text: _audienceLabel(gym.audience)),
                _InfoPill(icon: Icons.fitness_center_outlined, text: '${gym.trainersCount} مدربين'),
                _InfoPill(icon: Icons.people_outline, text: '${gym.membersCount} أعضاء'),
              ],
            ),
            if (gym.amenities.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: gym.amenities
                    .take(4)
                    .map((item) => Chip(label: Text(item)))
                    .toList(growable: false),
              ),
            ],
            if (gym.description != null && gym.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                gym.description!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserMarketplaceDetailPage(gymId: gym.id, gymName: gym.name),
                        ),
                      );
                    },
                    child: const Text('التفاصيل'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _joinGym(gym.id),
                    child: const Text('انضمام'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _joinGym(String gymId) async {
    try {
      await _api.joinGymAsUser(gymId);
      _showMessage('تم الانضمام للنادي');
    } catch (_) {
      _showMessage('تعذر الانضمام للنادي');
    }
  }

  void _filterByCity() {
    setState(() {
      _gymsFuture = _api.fetchPublicGyms(
        city: _cityController.text,
        audience: _audienceFilter,
      );
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _gymsFuture = _api.fetchPublicGyms(
        city: _cityController.text,
        audience: _audienceFilter,
      );
    });

    await _gymsFuture;
  }

  void _reload() {
    setState(() {
      _gymsFuture = _api.fetchPublicGyms(
        city: _cityController.text,
        audience: _audienceFilter,
      );
    });
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _audienceLabel(String audience) {
    switch (audience) {
      case 'MEN_ONLY':
        return 'رجال فقط';
      case 'WOMEN_ONLY':
        return 'نساء فقط';
      default:
        return 'رجال ونساء';
    }
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.labelMedium),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.error_outline, size: 42, color: Colors.red.shade700),
        const SizedBox(height: 10),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
