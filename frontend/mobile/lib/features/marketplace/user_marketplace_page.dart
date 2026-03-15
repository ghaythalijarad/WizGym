import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import 'marketplace_api_service.dart';
import 'marketplace_models.dart';
import 'user_marketplace_detail_page.dart';

class UserMarketplacePage extends StatefulWidget {
  const UserMarketplacePage({super.key, this.session});

  final AuthSession? session;

  @override
  State<UserMarketplacePage> createState() => _UserMarketplacePageState();
}

class _UserMarketplacePageState extends State<UserMarketplacePage> {
  late final MarketplaceApiService _api;
  late Future<List<GymSummary>> _gymsFuture;
  final TextEditingController _nameController = TextEditingController();
  String _selectedCity = '';
  String _audienceFilter = '';
  // gymId -> membership status ('PENDING' | 'ACTIVE' | 'EXPIRED' | null)
  final Map<String, String?> _membershipStatus = {};

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.user, session: widget.session);
    _gymsFuture = _api.fetchPublicGyms();
    _loadMyMemberships();
  }

  Future<void> _loadMyMemberships() async {
    try {
      final memberships = await _api.fetchMyGymMemberships();
      if (!mounted) return;
      setState(() {
        for (final m in memberships) {
          if (m.isPending) {
            _membershipStatus[m.gymId] = 'PENDING';
          } else if (m.isActive && !m.isExpired) {
            _membershipStatus[m.gymId] = 'ACTIVE';
          } else if (m.isActive && m.isExpired) {
            _membershipStatus[m.gymId] = 'EXPIRED';
          }
        }
      });
    } catch (_) {
      // Silently degrade — membership status is cosmetic here
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
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
          final cities = gyms
              .map((g) => g.city)
              .where((c) => c.trim().isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          if (_selectedCity.isNotEmpty && !cities.contains(_selectedCity)) {
            _selectedCity = '';
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
            children: [
              // ── Page heading ────────────────────────────────────────
              RichText(
                text: TextSpan(
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                  children: const [
                    TextSpan(
                      text: 'استكشف ',
                    ),
                    TextSpan(
                      text: 'النوادي',
                      style: TextStyle(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'انضم إلى النادي المناسب وابدأ رحلتك التدريبية',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
              ),
              const SizedBox(height: 16),

              // ── Search field ─────────────────────────────────────────
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم النادي...',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  suffixIcon: _nameController.text.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _nameController.clear();
                            _applyFilters();
                          },
                        ),
                ),
                textInputAction: TextInputAction.search,
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _applyFilters(),
              ),
              const SizedBox(height: 12),

              // ── City filter ──────────────────────────────────────────
              if (cities.isNotEmpty)
                SizedBox(
                  height: 36,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(
                        label: 'كل المدن',
                        selected: _selectedCity.isEmpty,
                        onTap: () {
                          setState(() => _selectedCity = '');
                          _applyFilters();
                        },
                      ),
                      ...cities.map((city) => _FilterChip(
                            label: city,
                            selected: _selectedCity == city,
                            onTap: () {
                              setState(() => _selectedCity = city);
                              _applyFilters();
                            },
                          )),
                    ],
                  ),
                ),
              const SizedBox(height: 8),

              // ── Audience chips ───────────────────────────────────────
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _FilterChip(
                      label: 'الكل',
                      selected: _audienceFilter.isEmpty,
                      onTap: () {
                        setState(() => _audienceFilter = '');
                        _applyFilters();
                      },
                    ),
                    _FilterChip(
                      label: 'رجال فقط',
                      selected: _audienceFilter == 'MEN_ONLY',
                      onTap: () {
                        setState(() => _audienceFilter = 'MEN_ONLY');
                        _applyFilters();
                      },
                    ),
                    _FilterChip(
                      label: 'نساء فقط',
                      selected: _audienceFilter == 'WOMEN_ONLY',
                      onTap: () {
                        setState(() => _audienceFilter = 'WOMEN_ONLY');
                        _applyFilters();
                      },
                    ),
                    _FilterChip(
                      label: 'رجال ونساء',
                      selected: _audienceFilter == 'MIXED',
                      onTap: () {
                        setState(() => _audienceFilter = 'MIXED');
                        _applyFilters();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // ── Results ──────────────────────────────────────────────
              if (gyms.isEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF16162A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: AppTheme.gold.withValues(alpha: 0.10)),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.search_off_rounded,
                          size: 36, color: AppTheme.textMuted),
                      const SizedBox(height: 10),
                      Text('لا توجد نوادي مطابقة للبحث',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textMuted)),
                    ],
                  ),
                ),
              ...gyms.map((gym) => _buildGymCard(context, gym)),
            ],
          );
        },
      ),
    );
  }

  void _applyFilters() {
    final name = _nameController.text.trim();
    final city = _selectedCity.trim();

    setState(() {
      _gymsFuture = _api.fetchPublicGyms(
        name: name.isEmpty ? null : name,
        city: city.isEmpty ? null : city,
        audience: _audienceFilter,
      );
    });
  }

  Widget _buildGymCard(BuildContext context, GymSummary gym) {
    final scheme = Theme.of(context).colorScheme;
    final memberStatus = _membershipStatus[gym.id];

    final photos = <String>{
      ...gym.photoViewUrls
          .where((p) => p.trim().isNotEmpty)
          .map((p) => p.trim()),
      if (gym.coverImageUrl != null && gym.coverImageUrl!.trim().isNotEmpty)
        gym.coverImageUrl!.trim(),
      ...gym.photos.where((p) => p.trim().isNotEmpty).map((p) => p.trim()),
    }.toList(growable: false);

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
                      child: photos.isEmpty
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
                          : _GymPhotosSlideshow(urls: photos),
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
            // ── Membership status badge ──────────────────────────────
            if (memberStatus != null) ...[
              const SizedBox(height: 10),
              _MembershipStatusBadge(status: memberStatus),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => UserMarketplaceDetailPage(
                            gymId: gym.id,
                            gymName: gym.name,
                            session: widget.session,
                          ),
                        ),
                      );
                    },
                    child: const Text('التفاصيل'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: memberStatus == 'ACTIVE'
                      ? OutlinedButton.icon(
                          onPressed: null,
                          icon:
                              const Icon(Icons.check_circle_outline, size: 16),
                          label: const Text('عضو فعّال'),
                        )
                      : memberStatus == 'PENDING'
                          ? OutlinedButton.icon(
                              onPressed: null,
                              icon: const Icon(Icons.hourglass_top_outlined,
                                  size: 16),
                              label: const Text('بانتظار الموافقة'),
                            )
                          : ElevatedButton(
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
    // Fetch subscription plans for this gym
    try {
      final plans = await _api.fetchSubscriptionPlans(gymId);
      final activePlans = plans.where((p) => p.isActive).toList();

      if (activePlans.isEmpty) {
        // No plans — join directly
        try {
          await _api.joinGymAsUser(gymId);
          if (mounted) setState(() => _membershipStatus[gymId] = 'PENDING');
          _showMessage('تم إرسال طلب الانضمام — بانتظار موافقة المالك');
          return;
        } on ApiException catch (e) {
          if (e.isConflict && _looksLikeActiveMembershipWarning(e.message)) {
            final confirmed = await _confirmJoinDespiteActiveMembership();
            if (confirmed != true) return;
            await _api.joinGymAsUser(gymId, forceJoin: true);
            if (mounted) setState(() => _membershipStatus[gymId] = 'PENDING');
            _showMessage('تم إرسال طلب الانضمام — بانتظار موافقة المالك');
            return;
          }
          rethrow;
        }
      }

      // Show plan selection dialog
      if (!mounted) return;
      final selectedPlan = await showModalBottomSheet<GymSubscriptionPlan>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _PlanSelectionSheet(plans: activePlans),
      );

      if (selectedPlan == null) return; // user cancelled

      try {
        final result =
            await _api.joinGymAsUser(gymId, planId: selectedPlan.planId);
        if (mounted) setState(() => _membershipStatus[gymId] = 'PENDING');
        final msg = result['message']?.toString();
        _showMessage(msg ??
            'تم إرسال طلب الانضمام بخطة "${selectedPlan.title}" — بانتظار موافقة المالك');
      } on ApiException catch (e) {
        if (e.isConflict && _looksLikeActiveMembershipWarning(e.message)) {
          final confirmed = await _confirmJoinDespiteActiveMembership();
          if (confirmed != true) return;
          final result = await _api.joinGymAsUser(
            gymId,
            planId: selectedPlan.planId,
            forceJoin: true,
          );
          if (mounted) setState(() => _membershipStatus[gymId] = 'PENDING');
          final msg = result['message']?.toString();
          _showMessage(msg ??
              'تم إرسال طلب الانضمام بخطة "${selectedPlan.title}" — بانتظار موافقة المالك');
          return;
        }
        rethrow;
      }
    } on ApiException catch (e) {
      if (e.isConflict || e.isBadRequest) {
        _showMessage(e.message);
      } else {
        _showMessage('تعذر الانضمام للنادي');
      }
    } catch (_) {
      _showMessage('تعذر الانضمام للنادي');
    }
  }

  bool _looksLikeActiveMembershipWarning(String message) {
    // Backend returns 409 with code HAS_ACTIVE_MEMBERSHIP; the client only
    // carries the message string today, so match on a stable Arabic fragment.
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

  Future<void> _refresh() async {
    _applyFilters();

    await _gymsFuture;
  }

  void _reload() {
    _applyFilters();
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

class _MembershipStatusBadge extends StatelessWidget {
  const _MembershipStatusBadge({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final Color color;
    final IconData icon;
    final String label;

    switch (status) {
      case 'ACTIVE':
        color = Colors.green;
        icon = Icons.check_circle_outline;
        label = 'عضو فعّال في هذا النادي';
        break;
      case 'PENDING':
        color = Colors.orange;
        icon = Icons.hourglass_top_outlined;
        label = 'طلب الانضمام بانتظار الموافقة';
        break;
      case 'EXPIRED':
        color = Colors.red;
        icon = Icons.cancel_outlined;
        label = 'انتهى الاشتراك في هذا النادي';
        break;
      default:
        color = Colors.grey;
        icon = Icons.info_outline;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}

class _GymPhotosSlideshow extends StatefulWidget {
  const _GymPhotosSlideshow({required this.urls});

  final List<String> urls;

  @override
  State<_GymPhotosSlideshow> createState() => _GymPhotosSlideshowState();
}

class _GymPhotosSlideshowState extends State<_GymPhotosSlideshow> {
  late final PageController _controller;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          itemCount: widget.urls.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, i) {
            final url = widget.urls[i];
            return Image.network(
              url,
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
            );
          },
        ),
        if (widget.urls.length > 1)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(widget.urls.length, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  width: active ? 14 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: active ? 0.95 : 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                );
              }),
            ),
          ),
      ],
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.40)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppTheme.gold,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.gold.withValues(alpha: 0.15)
              : const Color(0xFF16162A),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected
                ? AppTheme.gold.withValues(alpha: 0.55)
                : AppTheme.gold.withValues(alpha: 0.14),
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? AppTheme.gold : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.gold.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppTheme.gold),
          const SizedBox(width: 5),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
          ),
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

class _PlanSelectionSheet extends StatelessWidget {
  const _PlanSelectionSheet({required this.plans});

  final List<GymSubscriptionPlan> plans;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF16162A),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.gold.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.card_membership_outlined,
                        size: 16, color: AppTheme.gold),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('اختر خطة الاشتراك',
                            style: tt.titleMedium?.copyWith(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w800,
                            )),
                        Text('اختر الخطة المناسبة قبل الانضمام',
                            style: tt.bodySmall
                                ?.copyWith(color: AppTheme.textMuted)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                  height: 1, color: AppTheme.gold.withValues(alpha: 0.10)),
              const SizedBox(height: 14),
              ...plans.map((plan) => _PlanCard(
                    plan: plan,
                    onTap: () => Navigator.of(context).pop(plan),
                  )),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('إلغاء'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({required this.plan, required this.onTap});

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
          color: AppTheme.gold.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.14),
                shape: BoxShape.circle,
                border:
                    Border.all(color: AppTheme.gold.withValues(alpha: 0.35)),
              ),
              child: Center(
                child: Text(
                  '${plan.durationMonths}',
                  style: tt.titleMedium?.copyWith(
                      color: AppTheme.gold, fontWeight: FontWeight.w800),
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
                          fontWeight: FontWeight.w700)),
                  Text(durationLabel,
                      style: tt.bodySmall?.copyWith(color: AppTheme.textMuted)),
                  if (plan.description != null &&
                      plan.description!.isNotEmpty)
                    Text(plan.description!,
                        style:
                            tt.bodySmall?.copyWith(color: AppTheme.textMuted),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${plan.price}',
                    style: tt.titleMedium?.copyWith(
                        color: AppTheme.gold,
                        fontWeight: FontWeight.w800,
                        height: 1)),
                Text(plan.currency,
                    style: tt.labelSmall?.copyWith(color: AppTheme.textMuted)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
