import 'package:flutter/material.dart';

import '../../core/models/app_role.dart';
import 'marketplace_api_service.dart';
import 'marketplace_models.dart';

class UserMarketplaceDetailPage extends StatefulWidget {
  const UserMarketplaceDetailPage({super.key, required this.gymId, required this.gymName});

  final String gymId;
  final String gymName;

  @override
  State<UserMarketplaceDetailPage> createState() => _UserMarketplaceDetailPageState();
}

class _UserMarketplaceDetailPageState extends State<UserMarketplaceDetailPage> {
  late final MarketplaceApiService _api;
  late Future<_GymDetailViewData> _dataFuture;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.user);
    _dataFuture = _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.gymName)),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_GymDetailViewData>(
          future: _dataFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(24),
                children: [
                  Icon(Icons.error_outline, size: 42, color: Colors.red.shade700),
                  const SizedBox(height: 10),
                  const Text('تعذر تحميل تفاصيل النادي', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  ElevatedButton(onPressed: _reload, child: const Text('إعادة المحاولة')),
                ],
              );
            }

            final data = snapshot.data!;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _HeaderCard(detail: data.detail),
                if ((data.detail.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    data.detail.description!,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ],
                if (data.detail.amenities.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Text('الخدمات المتوفرة', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: data.detail.amenities
                        .map((item) => Chip(label: Text(item)))
                        .toList(growable: false),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _joinGym,
                        child: const Text('انضمام للنادي'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _rateGym,
                        child: const Text('تقييم النادي'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Text('المدربون', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (data.trainers.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('لا يمكن عرض المدربين حالياً. انضم للنادي أولاً.'),
                    ),
                  ),
                ...data.trainers.map((trainer) => _buildTrainerCard(trainer)),
                const SizedBox(height: 18),
                Text('مرافق النادي', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ...data.detail.facilities.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item.name),
                      subtitle: item.description == null ? null : Text(item.description!),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('منتجات وإعلانات', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                ...data.detail.products.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text(item.title),
                      subtitle: Text(item.description ?? '-'),
                      trailing: Text(item.price == null ? '' : '${item.price} د.ع'),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildTrainerCard(GymTrainerItem trainer) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(trainer.displayName, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text('التقييم: ${trainer.averageRating.toStringAsFixed(1)} ⭐'),
            Text('عملاء نشطون: ${trainer.activeClients}'),
            if (trainer.hiredByRequester)
              Text(
                'مدربك الحالي',
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rateTrainer(trainer.trainerId),
                    child: const Text('تقييم المدرب'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _hireTrainer(trainer.trainerId),
                    child: const Text('توظيفه'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<_GymDetailViewData> _loadData() async {
    final detail = await _api.fetchGymDetail(widget.gymId);

    try {
      final trainers = await _api.fetchGymTrainers(widget.gymId);
      return _GymDetailViewData(detail: detail, trainers: trainers);
    } catch (_) {
      return _GymDetailViewData(detail: detail, trainers: const []);
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

  Future<void> _joinGym() async {
    try {
      await _api.joinGymAsUser(widget.gymId);
      _showMessage('تم الانضمام بنجاح');
      _reload();
    } catch (_) {
      _showMessage('تعذر الانضمام');
    }
  }

  Future<void> _hireTrainer(String trainerId) async {
    try {
      await _api.hireTrainer(widget.gymId, trainerId);
      _showMessage('تم توظيف المدرب بنجاح');
      _reload();
    } catch (_) {
      _showMessage('تعذر توظيف المدرب');
    }
  }

  Future<void> _rateGym() async {
    final rating = await _openRatingDialog(title: 'تقييم النادي');
    if (rating == null) {
      return;
    }

    try {
      await _api.rateGym(
        gymId: widget.gymId,
        rating: rating.rating,
        comment: rating.comment,
      );
      _showMessage('تم إرسال تقييم النادي');
      _reload();
    } catch (_) {
      _showMessage('تعذر إرسال التقييم');
    }
  }

  Future<void> _rateTrainer(String trainerId) async {
    final rating = await _openRatingDialog(title: 'تقييم المدرب');
    if (rating == null) {
      return;
    }

    try {
      await _api.rateTrainer(
        trainerId: trainerId,
        gymId: widget.gymId,
        rating: rating.rating,
        comment: rating.comment,
      );
      _showMessage('تم إرسال تقييم المدرب');
      _reload();
    } catch (_) {
      _showMessage('تعذر إرسال تقييم المدرب');
    }
  }

  Future<_RatingInput?> _openRatingDialog({required String title}) async {
    int selectedRating = 5;
    final commentController = TextEditingController();

    final result = await showDialog<_RatingInput>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<int>(
                    initialValue: selectedRating,
                    decoration: const InputDecoration(labelText: 'عدد النجوم'),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('1')),
                      DropdownMenuItem(value: 2, child: Text('2')),
                      DropdownMenuItem(value: 3, child: Text('3')),
                      DropdownMenuItem(value: 4, child: Text('4')),
                      DropdownMenuItem(value: 5, child: Text('5')),
                    ],
                    onChanged: (value) {
                      if (value == null) {
                        return;
                      }

                      setDialogState(() {
                        selectedRating = value;
                      });
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: commentController,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'تعليق (اختياري)'),
                  ),
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _RatingInput(
                    rating: selectedRating,
                    comment: commentController.text,
                  ),
                );
              },
              child: const Text('إرسال'),
            ),
          ],
        );
      },
    );

    commentController.dispose();
    return result;
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.detail});

  final GymDetail detail;

  @override
  Widget build(BuildContext context) {
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
                height: 170,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: detail.coverImageUrl == null || detail.coverImageUrl!.isEmpty
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
                              child: const Icon(Icons.apartment_rounded, size: 52),
                            )
                          : Image.network(
                              detail.coverImageUrl!,
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
                                child: const Icon(Icons.image_not_supported_outlined, size: 40),
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
                              Colors.black.withValues(alpha: 0.62),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.name,
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _Pill(text: detail.city, icon: Icons.location_on_outlined),
                              _Pill(text: _audienceLabel(detail.audience), icon: Icons.groups_outlined),
                              _Pill(text: '${detail.averageRating.toStringAsFixed(1)} ★', icon: Icons.star_border_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المالك: ${detail.ownerName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
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

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.icon});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white.withValues(alpha: 0.92)),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Colors.white,
                ),
          ),
        ],
      ),
    );
  }
}

class _GymDetailViewData {
  const _GymDetailViewData({required this.detail, required this.trainers});

  final GymDetail detail;
  final List<GymTrainerItem> trainers;
}

class _RatingInput {
  const _RatingInput({required this.rating, required this.comment});

  final int rating;
  final String comment;
}
