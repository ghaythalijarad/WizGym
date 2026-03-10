import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../plans/plans_api_service.dart';
import 'marketplace_api_service.dart';
import 'marketplace_models.dart';

class UserMarketplaceDetailPage extends StatefulWidget {
  const UserMarketplaceDetailPage({
    super.key,
    required this.gymId,
    required this.gymName,
    this.session,
  });

  final String gymId;
  final String gymName;
  final AuthSession? session;

  @override
  State<UserMarketplaceDetailPage> createState() => _UserMarketplaceDetailPageState();
}

class _UserMarketplaceDetailPageState extends State<UserMarketplaceDetailPage> {
  late final MarketplaceApiService _api;
  PlansApiService? _plansApi;
  final AuthSessionStore _sessionStore = AuthSessionStore();
  late Future<_GymDetailViewData> _dataFuture;
  // trainerId -> subscription status ('PENDING'|'APPROVED'|null)
  final Map<String, String?> _subStatus = {};
  // gym join status: null | 'PENDING' | 'ACTIVE'
  String? _joinStatus;
  // The user's own membership for this gym (null = not a member)
  GymMemberItem? _myMembership;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.user, session: widget.session);
    _dataFuture = _loadData();
    _initPlansApi();
    _loadMyMembership();
  }

  Future<void> _loadMyMembership() async {
    try {
      final membership = await _api.fetchMyMembership(widget.gymId);
      if (mounted) {
        setState(() {
          _myMembership = membership;
          if (membership != null) {
            _joinStatus = membership.status;
          }
        });
      }
    } catch (_) {
      // Silently ignore — user may not be a member
    }
  }

  Future<void> _initPlansApi() async {
    final session = widget.session ?? await _sessionStore.load();
    final api = PlansApiService(role: AppRole.trainee, session: session);
    // Pre-load subscription statuses
    try {
      final subs = await api.fetchMySubscriptions();
      if (mounted) {
        setState(() {
          _plansApi = api;
          for (final s in subs) {
            _subStatus[s.trainerId] = s.status;
          }
        });
      }
    } catch (_) {
      if (mounted) setState(() => _plansApi = api);
    }
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
                // ── Subscription Plans ──
                if (data.detail.subscriptionPlans.isNotEmpty) ...[
                  Text('خطط الاشتراك',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  ...data.detail.subscriptionPlans.map(
                    (plan) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text('${plan.durationMonths}',
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        title: Text(plan.title),
                        subtitle: Text(
                          '${plan.durationMonths} ${plan.durationMonths == 1 ? 'شهر' : 'أشهر'}',
                        ),
                        trailing: Text(
                          '${plan.price} ${plan.currency}',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        onTap: () => _joinGymWithPlan(plan.planId),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                // ── My membership status card ──
                if (_myMembership != null) _buildMyMembershipCard(context),
                if (_myMembership != null) const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _joinStatus == 'PENDING'
                          ? OutlinedButton.icon(
                              onPressed: () => _cancelSubscription('CURRENT'),
                              icon: const Icon(Icons.hourglass_top, size: 16),
                              label: const Text('إلغاء طلب الانضمام'),
                              style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red),
                            )
                          : _joinStatus == 'ACTIVE'
                              ? FilledButton.icon(
                                  onPressed: null,
                                  icon: const Icon(Icons.check, size: 16),
                                  label: const Text('عضو في النادي'),
                                )
                              : ElevatedButton(
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
    final status = _subStatus[trainer.trainerId];
    final isApproved = status == 'APPROVED';
    final isPending = status == 'PENDING';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(
                    trainer.displayName.isNotEmpty
                        ? trainer.displayName[0].toUpperCase()
                        : '؟',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(trainer.displayName,
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        'التقييم: ${trainer.averageRating.toStringAsFixed(1)} ⭐  |  عملاء: ${trainer.activeClients}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isApproved) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 16),
                    SizedBox(width: 6),
                    Text('مدربك المعتمد',
                        style: TextStyle(
                            color: Colors.green, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _rateTrainer(trainer.trainerId),
                    child: const Text('تقييم'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: isApproved
                      ? FilledButton.icon(
                          onPressed: null,
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('مشترك'),
                        )
                      : isPending
                          ? OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.hourglass_top, size: 16),
                              label: const Text('بانتظار الموافقة'),
                            )
                          : FilledButton.icon(
                              onPressed: () =>
                                  _subscribeToTrainer(trainer.trainerId),
                              icon: const Icon(Icons.person_add_outlined,
                                  size: 16),
                              label: const Text('طلب اشتراك'),
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
    _loadMyMembership();
    await _dataFuture;
  }

  void _reload() {
    setState(() {
      _dataFuture = _loadData();
    });
    _loadMyMembership();
  }

  Future<void> _joinGym() async {
    try {
      final result = await _api.joinGymAsUser(widget.gymId);
      final status = result['status']?.toString() ?? 'PENDING';
      setState(() => _joinStatus = status);
      _showMessage(status == 'PENDING'
          ? 'تم إرسال طلب الانضمام — بانتظار موافقة المالك'
          : 'تم الانضمام بنجاح');
      _reload();
    } on ApiException catch (e) {
      if (e.isConflict || e.isBadRequest) {
        _showMessage(e.message);
      } else {
        _showMessage('تعذر الانضمام');
      }
    } catch (_) {
      _showMessage('تعذر الانضمام');
    }
  }

  Future<void> _joinGymWithPlan(String planId) async {
    try {
      final result = await _api.joinGymAsUser(widget.gymId, planId: planId);
      final msg = result['message']?.toString();
      final status = result['status']?.toString();
      // The backend may return a renewal-queued message or a PENDING status
      if (msg != null && msg.isNotEmpty) {
        _showMessage(msg);
      } else {
        setState(() => _joinStatus = status ?? 'PENDING');
        _showMessage(status == 'PENDING'
            ? 'تم إرسال طلب الانضمام مع الخطة — بانتظار موافقة المالك'
            : 'تم الانضمام بنجاح');
      }
      _reload();
    } on ApiException catch (e) {
      if (e.isConflict || e.isBadRequest) {
        _showMessage(e.message);
      } else {
        _showMessage('تعذر الانضمام');
      }
    } catch (_) {
      _showMessage('تعذر الانضمام');
    }
  }

  /// Cancel a subscription that hasn't started yet.
  Future<void> _cancelSubscription(String target) async {
    final label = target == 'NEXT' ? 'الخطة التالية' : 'الاشتراك';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الاشتراك'),
        content: Text('هل تريد إلغاء $label؟ يمكنك الإلغاء فقط إذا لم تبدأ الخطة بعد.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إلغاء الاشتراك'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final result = await _api.cancelSubscription(widget.gymId, target: target);
      final msg = result['message']?.toString() ?? 'تم الإلغاء بنجاح';
      _showMessage(msg);
      // Refresh membership state
      await _loadMyMembership();
      _reload();
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('تعذر إلغاء الاشتراك');
    }
  }

  /// Builds a card showing the user's current membership & subscription info.
  Widget _buildMyMembershipCard(BuildContext context) {
    final m = _myMembership!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Determine current plan label
    String? currentPlanLabel;
    if (m.selectedPlanTitle != null) {
      final dur = m.selectedPlanDurationMonths;
      currentPlanLabel = dur != null
          ? '${m.selectedPlanTitle} ($dur ${dur == 1 ? 'شهر' : 'أشهر'})'
          : m.selectedPlanTitle;
    }

    // Dates
    final expiryDate = m.subscriptionExpiresAt != null
        ? _formatDate(m.subscriptionExpiresAt!)
        : null;
    final expired = m.isExpired;

    // Next plan
    String? nextPlanLabel;
    if (m.hasNextPlan) {
      final npTitle = m.nextPlanTitle ?? 'خطة تالية';
      final npDur = m.nextPlanDurationMonths;
      nextPlanLabel = npDur != null
          ? '$npTitle ($npDur ${npDur == 1 ? 'شهر' : 'أشهر'})'
          : npTitle;
    }
    final nextStartDate = m.nextPlanStartsAt != null
        ? _formatDate(m.nextPlanStartsAt!)
        : null;

    // Can cancel next plan? (hasn't started yet)
    final canCancelNext = m.hasNextPlan &&
        m.nextPlanStartsAt != null &&
        DateTime.tryParse(m.nextPlanStartsAt!)?.isAfter(DateTime.now()) == true;

    return Card(
      color: scheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.card_membership, size: 20, color: scheme.primary),
                const SizedBox(width: 8),
                Text('اشتراكي', style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                )),
              ],
            ),
            const SizedBox(height: 10),
            // Current plan
            if (currentPlanLabel != null) ...[
              _InfoRow(
                icon: Icons.check_circle_outline,
                iconColor: expired ? Colors.red : Colors.green,
                label: 'الخطة الحالية',
                value: currentPlanLabel,
              ),
              if (expiryDate != null)
                _InfoRow(
                  icon: expired ? Icons.warning_amber_rounded : Icons.event_available,
                  iconColor: expired ? Colors.red : Colors.green,
                  label: expired ? 'انتهت في' : 'تنتهي في',
                  value: expiryDate,
                ),
              if (expired)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'اشتراك منتهي — يمكنك تجديده باختيار خطة جديدة',
                      style: TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
            if (currentPlanLabel == null && m.status == 'PENDING')
              const _InfoRow(
                icon: Icons.hourglass_top,
                iconColor: Colors.orange,
                label: 'الحالة',
                value: 'بانتظار موافقة المالك',
              ),
            if (currentPlanLabel == null && m.status == 'ACTIVE')
              _InfoRow(
                icon: Icons.info_outline,
                iconColor: scheme.primary,
                label: 'الحالة',
                value: 'عضو بدون خطة — اختر خطة أعلاه',
              ),
            // Next plan
            if (nextPlanLabel != null) ...[
              const Divider(height: 20),
              _InfoRow(
                icon: Icons.update,
                iconColor: scheme.tertiary,
                label: 'الخطة التالية',
                value: nextPlanLabel,
              ),
              if (nextStartDate != null)
                _InfoRow(
                  icon: Icons.calendar_today,
                  iconColor: scheme.tertiary,
                  label: 'تبدأ في',
                  value: nextStartDate,
                ),
              if (canCancelNext)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _cancelSubscription('NEXT'),
                      icon: const Icon(Icons.cancel_outlined, size: 16),
                      label: const Text('إلغاء الخطة التالية'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(String isoDate) {
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }

  Future<void> _subscribeToTrainer(String trainerId) async {
    final api = _plansApi;
    if (api == null) {
      _showMessage('جاري التحضير، حاول مجدداً');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('طلب اشتراك'),
        content: const Text(
            'سيتم إرسال طلب اشتراكك إلى المدرب. بعد موافقته يمكنه إرسال خطط تدريبية لك.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('إرسال الطلب'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await api.subscribeToTrainer(trainerId: trainerId, gymId: widget.gymId);
      setState(() => _subStatus[trainerId] = 'PENDING');
      _showMessage('تم إرسال طلب الاشتراك بنجاح ✓');
    } catch (e) {
      _showMessage('تعذر إرسال الطلب: $e');
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
