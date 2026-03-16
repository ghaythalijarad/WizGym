import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
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
  // trainerId -> public profile (bio + avatar)
  final Map<String, TrainerPublicProfile> _trainerProfiles = {};
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

            final tt = Theme.of(context).textTheme;

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
              children: [
                _HeaderCard(detail: data.detail),

                // ── Description ─────────────────────────────────────────
                if ((data.detail.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF16162A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppTheme.gold.withValues(alpha: 0.12)),
                    ),
                    child: Text(
                      data.detail.description!,
                      style: tt.bodyMedium?.copyWith(
                          color: AppTheme.textSecondary, height: 1.6),
                    ),
                  ),
                ],

                // ── Amenities ────────────────────────────────────────────
                if (data.detail.amenities.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const _DetailSectionHeader(
                      label: 'الخدمات المتوفرة',
                      icon: Icons.star_outline_rounded),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: data.detail.amenities
                        .map((item) => _GoldChip(label: item))
                        .toList(growable: false),
                  ),
                ],

                // ── Opening hours ────────────────────────────────────────
                if (data.detail.openingHours != null &&
                    data.detail.openingHours!.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  const _DetailSectionHeader(
                      label: 'أوقات الدوام',
                      icon: Icons.schedule_rounded),
                  const SizedBox(height: 10),
                  _OpeningHoursCard(hours: data.detail.openingHours!),
                ],

                const SizedBox(height: 18),

                // ── Membership / join action ─────────────────────────────
                if (_myMembership != null) ...[
                  _buildMyMembershipCard(context),
                  const SizedBox(height: 10),
                ],
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
                              : FilledButton.icon(
                                  onPressed: _joinGym,
                                  icon: const Icon(Icons.fitness_center_rounded,
                                      size: 16),
                                  label: const Text('انضمام للنادي'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppTheme.gold,
                                    foregroundColor: AppTheme.textOnGold,
                                  ),
                                ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _rateGym,
                      icon: const Icon(Icons.star_border_rounded, size: 16),
                      label: const Text('تقييم'),
                    ),
                  ],
                ),

                // ── Subscription Plans ────────────────────────────────────
                if (data.detail.subscriptionPlans.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const _DetailSectionHeader(
                      label: 'خطط الاشتراك',
                      icon: Icons.card_membership_outlined),
                  const SizedBox(height: 10),
                  ...data.detail.subscriptionPlans.map(
                    (plan) => _PremiumPlanCard(
                      plan: plan,
                      onTap: () => _joinGymWithPlan(plan.planId),
                    ),
                  ),
                ],

                // ── Trainers ──────────────────────────────────────────────
                const SizedBox(height: 22),
                const _DetailSectionHeader(
                    label: 'المدربون', icon: Icons.sports_outlined),
                const SizedBox(height: 10),
                if (data.trainers.isEmpty)
                  const _EmptySection(
                      message:
                          'لا يمكن عرض المدربين حالياً. انضم للنادي أولاً.'),
                ...data.trainers.map((trainer) => _buildTrainerCard(trainer)),

                // ── Facilities ────────────────────────────────────────────
                if (data.detail.facilities.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const _DetailSectionHeader(
                      label: 'مرافق النادي', icon: Icons.construction_outlined),
                  const SizedBox(height: 10),
                  ...data.detail.facilities.map(
                    (item) => _AssetRow(
                      title: item.name,
                      subtitle: item.description,
                      icon: Icons.construction_outlined,
                    ),
                  ),
                ],

                // ── Products ──────────────────────────────────────────────
                if (data.detail.products.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  const _DetailSectionHeader(
                      label: 'منتجات وإعلانات',
                      icon: Icons.storefront_outlined),
                  const SizedBox(height: 10),
                  ...data.detail.products.map(
                    (item) => _AssetRow(
                      title: item.title,
                      subtitle: item.description,
                      trailing: item.price != null ? '${item.price} د.ع' : null,
                      icon: Icons.storefront_outlined,
                    ),
                  ),
                ],

                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _openTrainerCertificates(
      String trainerId, String trainerName) async {
    try {
      final certs = await _api.fetchTrainerCertificates(trainerId);
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: const Color(0xFF16162A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) {
          final theme = Theme.of(ctx);
          final scheme = theme.colorScheme;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Spacer(),
                      const Icon(Icons.verified_outlined,
                          size: 18, color: AppTheme.gold),
                      const SizedBox(width: 8),
                      Text(
                        'شهادات وأوسمة $trainerName',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: AppTheme.gold,
                          fontWeight: FontWeight.w800,
                        ),
                        textAlign: TextAlign.end,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (certs.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 16, horizontal: 14),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outline),
                      ),
                      child: Text(
                        'لا توجد شهادات/أوسمة مضافة حالياً.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: scheme.onSurfaceVariant),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: certs.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (ctx, i) {
                          final c = certs[i];
                          final yearLabel = c.year == null ? '' : '${c.year}';

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: scheme.surface,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(color: scheme.outline),
                            ),
                            child: Row(
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: SizedBox(
                                    width: 64,
                                    height: 64,
                                    child: Image.network(
                                      c.image.url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Container(
                                        color: scheme.surfaceContainerHighest,
                                        child: const Icon(
                                            Icons.image_not_supported_outlined,
                                            color: AppTheme.textMuted),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        c.name,
                                        textAlign: TextAlign.end,
                                        style: theme.textTheme.titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w800),
                                      ),
                                      if (yearLabel.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          yearLabel,
                                          textAlign: TextAlign.end,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant),
                                        ),
                                      ],
                                      if (c.description.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          c.description,
                                          textAlign: TextAlign.end,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color:
                                                      scheme.onSurfaceVariant),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      );
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('تعذر تحميل الشهادات/الأوسمة');
    }
  }

  Widget _buildTrainerCard(GymTrainerItem trainer) {
    final status = _subStatus[trainer.trainerId];
    final isApproved = status == 'APPROVED';
    final isPending = status == 'PENDING';
    final profile = _trainerProfiles[trainer.trainerId];
    final initial = trainer.displayName.isNotEmpty
        ? trainer.displayName[0].toUpperCase()
        : '؟';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isApproved
              ? AppTheme.gold.withValues(alpha: 0.35)
              : AppTheme.gold.withValues(alpha: 0.10),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Avatar — show photo if available, else initials
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: profile?.avatarUrl == null
                      ? const LinearGradient(
                          colors: [AppTheme.goldDeep, AppTheme.gold],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: AppTheme.gold.withValues(alpha: 0.3), width: 1.5),
                ),
                clipBehavior: Clip.antiAlias,
                child: profile?.avatarUrl != null
                    ? Image.network(
                        profile!.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Center(
                          child: Text(initial,
                              style: const TextStyle(
                                  color: AppTheme.textOnGold,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18)),
                        ),
                      )
                    : Center(
                        child: Text(initial,
                            style: const TextStyle(
                                color: AppTheme.textOnGold,
                                fontWeight: FontWeight.w800,
                                fontSize: 18)),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(trainer.displayName,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                            )),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(Icons.star_outline_rounded,
                            size: 13, color: AppTheme.gold),
                        const SizedBox(width: 3),
                        Text(trainer.averageRating.toStringAsFixed(1),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppTheme.textSecondary)),
                        const SizedBox(width: 10),
                        const Icon(Icons.people_outline,
                            size: 13, color: AppTheme.textMuted),
                        const SizedBox(width: 3),
                        Text('${trainer.activeClients} عميل',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: AppTheme.textMuted)),
                      ],
                    ),
                  ],
                ),
              ),
              // Approved badge
              if (isApproved)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: AppTheme.gold.withValues(alpha: 0.35)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          size: 13, color: AppTheme.gold),
                      SizedBox(width: 4),
                      Text('مدربك',
                          style: TextStyle(
                              color: AppTheme.gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
            ],
          ),
          // Bio — shown only for approved subscribers
          if (isApproved &&
              profile?.bio != null &&
              profile!.bio!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border:
                    Border.all(color: AppTheme.gold.withValues(alpha: 0.12)),
              ),
              child: Text(
                profile.bio!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSecondary,
                      height: 1.55,
                    ),
                textDirection: TextDirection.rtl,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _rateTrainer(trainer.trainerId),
                  child: const Text('تقييم'),
                ),
              ),
              const SizedBox(width: 10),
              if (isApproved) ...[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _openTrainerCertificates(
                      trainer.trainerId,
                      trainer.displayName,
                    ),
                    icon: const Icon(Icons.verified_outlined, size: 16),
                    label: const Text('الشهادات'),
                  ),
                ),
                const SizedBox(width: 10),
              ],
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
                            label: const Text('بانتظار موافقة المدرب'),
                          )
                        : FilledButton.icon(
                            onPressed: () =>
                                _subscribeToTrainer(trainer.trainerId),
                            icon:
                                const Icon(Icons.person_add_outlined, size: 16),
                            label: const Text('طلب اشتراك'),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.gold,
                              foregroundColor: AppTheme.textOnGold,
                            ),
                          ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<_GymDetailViewData> _loadData() async {
    final detail = await _api.fetchGymDetail(widget.gymId);

    try {
      final trainers = await _api.fetchGymTrainers(widget.gymId);

      // Fetch public profiles for all trainers in parallel (bio + avatar)
      final profiles = await Future.wait(
        trainers.map((t) => _api
            .fetchTrainerPublicProfile(t.trainerId)
            .catchError((_) => TrainerPublicProfile(
                  trainerId: t.trainerId,
                  displayName: t.displayName,
                ))),
      );
      if (mounted) {
        setState(() {
          for (final p in profiles) {
            _trainerProfiles[p.trainerId] = p;
          }
        });
      }

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
      if (e.isConflict && _looksLikeActiveMembershipWarning(e.message)) {
        final confirmed = await _confirmJoinDespiteActiveMembership();
        if (confirmed != true) return;
        final result = await _api.joinGymAsUser(widget.gymId, forceJoin: true);
        final status = result['status']?.toString() ?? 'PENDING';
        setState(() => _joinStatus = status);
        _showMessage(status == 'PENDING'
            ? 'تم إرسال طلب الانضمام — بانتظار موافقة المالك'
            : 'تم الانضمام بنجاح');
        _reload();
        return;
      }

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
      if (e.isConflict && _looksLikeActiveMembershipWarning(e.message)) {
        final confirmed = await _confirmJoinDespiteActiveMembership();
        if (confirmed != true) return;
        final result = await _api.joinGymAsUser(
          widget.gymId,
          planId: planId,
          forceJoin: true,
        );
        final msg = result['message']?.toString();
        final status = result['status']?.toString();
        if (msg != null && msg.isNotEmpty) {
          _showMessage(msg);
        } else {
          setState(() => _joinStatus = status ?? 'PENDING');
          _showMessage(status == 'PENDING'
              ? 'تم إرسال طلب الانضمام مع الخطة — بانتظار موافقة المالك'
              : 'تم الانضمام بنجاح');
        }
        _reload();
        return;
      }

      if (e.isConflict || e.isBadRequest) {
        _showMessage(e.message);
      } else {
        _showMessage('تعذر الانضمام');
      }
    } catch (_) {
      _showMessage('تعذر الانضمام');
    }
  }

  bool _looksLikeActiveMembershipWarning(String message) {
    return message.contains('اشتراك') && message.contains('نادي آخر');
  }

  Future<bool?> _confirmJoinDespiteActiveMembership() {
    if (!mounted) return Future.value(false);
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تنبيه'),
        content:
            const Text('لديك اشتراك فعّال في نادي آخر، هل تريد الاستمرار؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('استمرار'),
          ),
        ],
      ),
    );
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

    // Fetch trainer's available subscription plans
    List<TrainerSubscriptionPlan> trainerPlans = [];
    try {
      trainerPlans = await api.fetchTrainerSubscriptionPlans(trainerId);
    } catch (_) {
      trainerPlans = [];
    }
    if (!mounted) return;

    String? chosenPlanId; // null = dismissed, '' = no plan
    if (trainerPlans.isNotEmpty) {
      // Show plan picker sheet
      chosenPlanId = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF16162A),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => _TrainerPlanPickerSheet(
          plans: trainerPlans,
          trainerName: trainerId,
        ),
      );
      if (chosenPlanId == null) return; // dismissed
    } else {
      // No plans — confirm directly
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
      chosenPlanId = '';
    }

    try {
      await api.subscribeToTrainer(
        trainerId: trainerId,
        gymId: widget.gymId,
        planId: chosenPlanId.isEmpty ? null : chosenPlanId,
      );
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
    double selectedRating = 5.0;
    final commentController = TextEditingController();

    final result = await showDialog<_RatingInput>(
      context: context,
      builder: (ctx) {
        return Dialog(
          backgroundColor: const Color(0xFF16162A),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: StatefulBuilder(
              builder: (context, setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Title ─────────────────────────────────────
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.gold.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.star_rounded,
                              color: AppTheme.gold, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),

                    // ── Full-star picker ─────────────────────────
                    Center(
                      child: _HalfStarPicker(
                        value: selectedRating,
                        onChanged: (v) =>
                            setDialogState(() => selectedRating = v),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        _ratingLabel(selectedRating),
                        style: TextStyle(
                          color: AppTheme.gold.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // ── Comment field ─────────────────────────────
                    TextField(
                      controller: commentController,
                      maxLines: 3,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'تعليق (اختياري)',
                        labelStyle: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 13),
                        filled: true,
                        fillColor: const Color(0xFF1E1E35),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: AppTheme.gold.withValues(alpha: 0.2)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: AppTheme.gold.withValues(alpha: 0.6),
                              width: 1.5),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: AppTheme.gold.withValues(alpha: 0.2)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // ── Buttons ───────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppTheme.textSecondary,
                              side: BorderSide(
                                  color: AppTheme.textMuted
                                      .withValues(alpha: 0.4)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: const Text('إلغاء'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop(
                                _RatingInput(
                                  rating: selectedRating,
                                  comment: commentController.text,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppTheme.gold,
                              foregroundColor: AppTheme.textOnGold,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                            child: const Text('إرسال',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    commentController.dispose();
    return result;
  }

  String _ratingLabel(double r) {
    if (r <= 1) return 'سيء جداً';
    if (r <= 1.5) return 'سيء';
    if (r <= 2) return 'ضعيف';
    if (r <= 2.5) return 'مقبول';
    if (r <= 3) return 'متوسط';
    if (r <= 3.5) return 'جيد';
    if (r <= 4) return 'جيد جداً';
    if (r <= 4.5) return 'ممتاز';
    return 'رائع! ⭐';
  }

  void _showMessage(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _HeaderCard extends StatefulWidget {
  const _HeaderCard({required this.detail});

  final GymDetail detail;

  @override
  State<_HeaderCard> createState() => _HeaderCardState();
}

class _HeaderCardState extends State<_HeaderCard> {
  late final PageController _pageController;
  int _currentPage = 0;

  List<String> get _images {
    final urls = <String>[];
    // Prefer the rich photoViewUrls list; fall back to coverImageUrl
    if (widget.detail.photoViewUrls.isNotEmpty) {
      urls.addAll(widget.detail.photoViewUrls);
    } else if (widget.detail.coverImageUrl != null &&
        widget.detail.coverImageUrl!.isNotEmpty) {
      urls.add(widget.detail.coverImageUrl!);
    }
    return urls;
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void didUpdateWidget(covariant _HeaderCard oldWidget) {
    super.didUpdateWidget(oldWidget);

    // If images list changes after async refresh, keep controller but ensure
    // current page stays within valid bounds.
    final images = _images;
    final maxIndex = images.isEmpty ? 0 : images.length - 1;
    if (_currentPage > maxIndex) {
      setState(() => _currentPage = 0);
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final images = _images;
    final hasImages = images.isNotEmpty;
    final multiPage = images.length > 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: SizedBox(
                  height: 200,
                  child: Stack(
                  children: [
                      // ── Photo PageView ──────────────────────────
                    Positioned.fill(
                        child: !hasImages
                          ? DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [
                                    scheme.primary.withValues(alpha: 0.14),
                                      scheme.secondary.withValues(alpha: 0.10),
                                  ],
                                ),
                              ),
                                child: const Icon(Icons.apartment_rounded,
                                    size: 52),
                            )
                            : PageView.builder(
                                controller: _pageController,
                                itemCount: images.length,
                                onPageChanged: (i) =>
                                    setState(() => _currentPage = i),
                                itemBuilder: (_, i) => Image.network(
                                  images[i],
                                  key: ValueKey(images[i]),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topRight,
                                        end: Alignment.bottomLeft,
                                        colors: [
                                          scheme.primary
                                              .withValues(alpha: 0.14),
                                          scheme.secondary
                                              .withValues(alpha: 0.10),
                                        ],
                                      ),
                                    ),
                                    child: const Icon(
                                        Icons.image_not_supported_outlined,
                                        size: 40),
                                  ),
                                ),
                              ),
                      ),
                      // ── Bottom gradient scrim ──────────────────
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                                Colors.black.withValues(alpha: 0.68),
                              Colors.transparent,
                            ],
                              stops: const [0.0, 0.55],
                          ),
                        ),
                      ),
                    ),
                      // ── Name + pills ───────────────────────────
                    Positioned(
                      left: 12,
                      right: 12,
                        bottom: multiPage ? 30 : 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              widget.detail.name,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                              runSpacing: 6,
                            children: [
                                _Pill(
                                    text: widget.detail.city,
                                    icon: Icons.location_on_outlined),
                                _Pill(
                                    text:
                                        _audienceLabel(widget.detail.audience),
                                    icon: Icons.groups_outlined),
                                _Pill(
                                    text:
                                        '${widget.detail.averageRating.toStringAsFixed(1)} ★',
                                    icon: Icons.star_border_rounded),
                            ],
                          ),
                        ],
                      ),
                    ),
                      // ── Page indicator dots ────────────────────
                      if (multiPage)
                        Positioned(
                          bottom: 10,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(images.length, (i) {
                              final active = i == _currentPage;
                              return AnimatedContainer(
                                duration: const Duration(milliseconds: 220),
                                margin:
                                    const EdgeInsets.symmetric(horizontal: 3),
                                width: active ? 18 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppTheme.gold
                                      : Colors.white.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              );
                            }),
                          ),
                        ),
                      // ── Left / Right arrow taps ────────────────
                      if (multiPage) ...[
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          width: 48,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (_currentPage > 0) {
                                _pageController.previousPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              }
                            },
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          width: 48,
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () {
                              if (_currentPage < images.length - 1) {
                                _pageController.nextPage(
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              }
                            },
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'المالك: ${widget.detail.ownerName}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ),
                if (multiPage)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(
                      '${_currentPage + 1} / ${images.length}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.textMuted,
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

// ─────────────────────────────────────────────────────────────────────────────
// Section heading with gold accent line
// ─────────────────────────────────────────────────────────────────────────────

class _DetailSectionHeader extends StatelessWidget {
  const _DetailSectionHeader({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppTheme.gold.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: AppTheme.gold),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppTheme.gold.withValues(alpha: 0.30),
                Colors.transparent,
              ]),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Gold amenity chip
// ─────────────────────────────────────────────────────────────────────────────

class _GoldChip extends StatelessWidget {
  const _GoldChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: AppTheme.goldLight,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Premium plan card used in the detail page
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumPlanCard extends StatelessWidget {
  const _PremiumPlanCard({required this.plan, required this.onTap});

  final GymSubscriptionPlan plan;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final durationLabel = plan.durationMonths == 1
        ? 'شهر واحد'
        : plan.durationMonths == 2
            ? 'شهرين'
            : '${plan.durationMonths} أشهر';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            // Duration circle
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppTheme.gold.withValues(alpha: 0.35)),
              ),
              child: Center(
                child: Text(
                  '${plan.durationMonths}',
                  style: tt.titleMedium?.copyWith(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(plan.title,
                      style: tt.titleSmall?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 2),
                  Text(durationLabel,
                      style: tt.bodySmall?.copyWith(color: AppTheme.textMuted)),
                  if (plan.description != null &&
                      plan.description!.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(plan.description!,
                        style:
                            tt.bodySmall?.copyWith(color: AppTheme.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${plan.price}',
                  style: tt.titleLarge?.copyWith(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                ),
                Text(
                  plan.currency,
                  style: tt.labelSmall?.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Compact facility / product row
// ─────────────────────────────────────────────────────────────────────────────

class _AssetRow extends StatelessWidget {
  const _AssetRow({
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final String? trailing;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.10)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 16, color: AppTheme.gold),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    )),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      style: tt.bodySmall?.copyWith(color: AppTheme.textMuted),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border:
                    Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
              ),
              child: Text(trailing!,
                  style: tt.labelSmall?.copyWith(
                    color: AppTheme.gold,
                    fontWeight: FontWeight.w700,
                  )),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state inline
// ─────────────────────────────────────────────────────────────────────────────

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.08)),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppTheme.textMuted),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _GymDetailViewData {
  const _GymDetailViewData({required this.detail, required this.trainers});

  final GymDetail detail;
  final List<GymTrainerItem> trainers;
}

class _RatingInput {
  const _RatingInput({required this.rating, required this.comment});

  final double rating;
  final String comment;
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-star interactive picker (1 … 5)
// ─────────────────────────────────────────────────────────────────────────────

class _HalfStarPicker extends StatelessWidget {
  const _HalfStarPicker({required this.value, required this.onChanged});

  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value.round().clamp(1, 5);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final starIndex = i + 1;
        final filled = starIndex <= selected;

        return IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => onChanged(starIndex.toDouble()),
          icon: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: 34,
            color: filled
                ? AppTheme.gold
                : AppTheme.textMuted.withValues(alpha: 0.55),
          ),
        );
      }),
    );
  }
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

// ─────────────────────────────────────────────────────────────────────────────
// Trainer subscription plan picker bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TrainerPlanPickerSheet extends StatelessWidget {
  const _TrainerPlanPickerSheet({
    required this.plans,
    required this.trainerName,
  });

  final List<TrainerSubscriptionPlan> plans;
  final String trainerName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted.withValues(alpha: 0.40),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.card_membership_outlined,
                    color: AppTheme.gold, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('اختر خطة الاشتراك',
                        style: theme.textTheme.titleMedium?.copyWith(
                            color: AppTheme.gold, fontWeight: FontWeight.w700)),
                    Text('اختر الخطة المناسبة لك',
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: AppTheme.textMuted)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            ...plans.map((p) => GestureDetector(
                  onTap: () => Navigator.of(context).pop(p.planId),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E1E35),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: AppTheme.gold.withValues(alpha: 0.22)),
                    ),
                    child: Row(children: [
                      // Duration circle
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppTheme.gold.withValues(alpha: 0.35)),
                        ),
                        child: Center(
                          child: Text('${p.durationMonths}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: AppTheme.gold,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: theme.textTheme.titleSmall?.copyWith(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w700)),
                            Text(p.durationLabel,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: AppTheme.textMuted)),
                            if (p.description.isNotEmpty)
                              Text(p.description,
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.textMuted),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(p.price.toStringAsFixed(0),
                              style: theme.textTheme.titleMedium?.copyWith(
                                  color: AppTheme.gold,
                                  fontWeight: FontWeight.w800)),
                          Text('د.ع',
                              style: theme.textTheme.labelSmall
                                  ?.copyWith(color: AppTheme.textMuted)),
                        ],
                      ),
                    ]),
                  ),
                )),
            // Option to subscribe without a plan
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(''),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.textSecondary,
                side: BorderSide(
                    color: AppTheme.textMuted.withValues(alpha: 0.30)),
              ),
              child: const Text('إرسال طلب بدون خطة'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Opening hours display card ──────────────────────────────────────────────
class _OpeningHoursCard extends StatelessWidget {
  const _OpeningHoursCard({required this.hours});

  final Map<String, DayHours> hours;

  @override
  Widget build(BuildContext context) {
    // Determine today's day key
    final now = DateTime.now();
    const dartWeekdayToKey = {
      DateTime.saturday: 'saturday',
      DateTime.sunday: 'sunday',
      DateTime.monday: 'monday',
      DateTime.tuesday: 'tuesday',
      DateTime.wednesday: 'wednesday',
      DateTime.thursday: 'thursday',
      DateTime.friday: 'friday',
    };
    final todayKey = dartWeekdayToKey[now.weekday] ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: kWeekDayKeys.map((day) {
          final label = kWeekDayLabelsAr[day] ?? day;
          final dh = hours[day];
          final isToday = day == todayKey;
          final isClosed = dh == null || dh.isEmpty;

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                if (isToday)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(left: 6),
                    decoration: const BoxDecoration(
                      color: AppTheme.gold,
                      shape: BoxShape.circle,
                    ),
                  ),
                SizedBox(
                  width: 70,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: isToday
                          ? AppTheme.gold
                          : AppTheme.textPrimary,
                      fontSize: 13,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isClosed ? 'مغلق' : '${dh.open} – ${dh.close}',
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      color: isClosed
                          ? AppTheme.textMuted.withValues(alpha: 0.5)
                          : isToday
                              ? AppTheme.gold
                              : AppTheme.textSecondary,
                      fontSize: 13,
                      fontWeight:
                          isToday ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(growable: false),
      ),
    );
  }
}
