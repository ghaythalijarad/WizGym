import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';
import '../marketplace/owner_gym_photos_section.dart';
import '../marketplace/owner_gym_subscription_request_section.dart';
import 'owner_create_gym_page.dart';

class OwnerHomePage extends StatefulWidget {
  const OwnerHomePage({super.key, this.session});

  final AuthSession? session;

  @override
  State<OwnerHomePage> createState() => _OwnerHomePageState();
}

class _OwnerHomePageState extends State<OwnerHomePage> {
  late final MarketplaceApiService _api;
  late Future<List<GymSummary>> _gymsFuture;

  @override
  void initState() {
    super.initState();
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
    _gymsFuture = _api.fetchOwnerGyms();
  }

  void _reload() {
    // Do NOT call async work inside setState — assign the future first,
    // then trigger a synchronous rebuild.
    final next = _api.fetchOwnerGyms();
    setState(() => _gymsFuture = next);
  }

  Future<void> _openCreateGym() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => OwnerCreateGymPage(session: widget.session),
      ),
    );
    if (result == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        _reload();
        await _gymsFuture;
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        children: [
          // ── Page heading ─────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('نواديي',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: AppTheme.gold,
                                  fontWeight: FontWeight.w800,
                                )),
                    Text(
                      'إدارة وتطوير نواديك',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.textMuted,
                          ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _openCreateGym,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('إنشاء نادي'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<GymSummary>>(
            future: _gymsFuture,
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final gyms = snap.data ?? [];
              if (gyms.isEmpty) {
                return const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child:
                        Text('لا توجد نوادي مملوكة لك حالياً. أنشئ نادي جديد!'),
                  ),
                );
              }
              return Column(
                children: gyms
                    .map((g) => _GymCard(
                          gym: g,
                          api: _api,
                          session: widget.session,
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GymCard extends StatefulWidget {
  const _GymCard({required this.gym, required this.api, this.session});
  final GymSummary gym;
  final MarketplaceApiService api;
  final AuthSession? session;

  @override
  State<_GymCard> createState() => _GymCardState();
}

class _GymCardState extends State<_GymCard> {
  bool _expanded = false;

  static const Map<String, String> _audienceAr = {
    'MEN_ONLY': 'رجال فقط',
    'WOMEN_ONLY': 'نساء فقط',
    'MIXED': 'رجال ونساء',
  };

  static const Map<String, String> _amenityAr = {
    'Food Bar': 'بار غذائي',
    'Sauna': 'ساونا',
    'Steam Room': 'غرفة بخار',
    'Pool': 'مسبح',
    'Parking': 'موقف سيارات',
    'Kids Area': 'منطقة أطفال',
    'Ice Bath': 'حمام ثلج',
    'Massage Room': 'غرفة مساج',
  };

  String _amenityLabel(String key) => _amenityAr[key] ?? key;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final gym = widget.gym;

    final isPending = gym.status == 'PENDING_APPROVAL';
    final isRejected = gym.status == 'REJECTED';
    // Amber darkened to #92400E — 7.2:1 on white ✓; use distinct amber bg
    const pendingColor = Color(0xFF92400E);
    final statusColor = isPending
        ? pendingColor
        : isRejected
            ? scheme.error
            : scheme.primary;
    // Badge bg: use fixed light tint for each state for consistent contrast
    final statusBgColor = isPending
        ? const Color(0xFFFEF3C7) // amber-50
        : isRejected
            ? scheme.errorContainer
            : scheme.primaryContainer;
    final statusLabel = isPending
        ? 'بانتظار الاعتماد'
        : isRejected
            ? 'مرفوض'
            : 'فعّال';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeInOut,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF16162A),
        border: Border.all(
          color: _expanded
              ? AppTheme.gold.withValues(alpha: 0.40)
              : AppTheme.gold.withValues(alpha: 0.12),
          width: _expanded ? 1.5 : 1.0,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: _expanded
            ? [
                BoxShadow(
                  color: AppTheme.gold.withValues(alpha: 0.08),
                  blurRadius: 16,
                  spreadRadius: 0,
                )
              ]
            : [],
      ),
      child: Column(
        children: [
          // ── Header ──────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Animated chevron
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 240),
                    child: const Icon(Icons.chevron_right,
                        size: 20, color: AppTheme.textMuted),
                  ),
                  const SizedBox(width: 10),
                  // Status badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: statusBgColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w700,
                        )),
                  ),
                  const Spacer(),
                  // Name + city
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(gym.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: AppTheme.textPrimary,
                            )),
                        Text(
                          '${gym.city} · ${gym.membersCount} عضو',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Gold icon box
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 240),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _expanded
                          ? AppTheme.gold.withValues(alpha: 0.18)
                          : AppTheme.gold.withValues(alpha: 0.09),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: AppTheme.gold
                            .withValues(alpha: _expanded ? 0.50 : 0.18),
                      ),
                    ),
                    child: Icon(Icons.fitness_center_rounded,
                        size: 18,
                        color: _expanded ? AppTheme.gold : AppTheme.textMuted),
                  ),
                ],
              ),
            ),
          ),

          // ── Expanded body ───────────────────────────────────
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 280),
            firstChild: const SizedBox.shrink(),
            secondChild: _ExpandedGymBody(
              gym: gym,
              api: widget.api,
              session: widget.session,
              audienceLabel: _audienceAr[gym.audience] ?? gym.audience,
              amenityLabel: _amenityLabel,
            ),
            crossFadeState: _expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Expanded body
// ─────────────────────────────────────────────────────────────────────────────

class _ExpandedGymBody extends StatelessWidget {
  const _ExpandedGymBody({
    required this.gym,
    required this.api,
    required this.audienceLabel,
    required this.amenityLabel,
    this.session,
  });

  final GymSummary gym;
  final MarketplaceApiService api;
  final AuthSession? session;
  final String audienceLabel;
  final String Function(String) amenityLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, color: scheme.outline),
          const SizedBox(height: 14),

          // ── Quick stats row ──────────────────────────────
          Row(
            children: [
              _InfoChip(
                icon: Icons.people_outline,
                label: '${gym.membersCount} عضو',
                scheme: scheme,
                theme: theme,
              ),
              const SizedBox(width: 8),
              _InfoChip(
                icon: Icons.fitness_center_outlined,
                label: '${gym.trainersCount} مدرب',
                scheme: scheme,
                theme: theme,
              ),
              const SizedBox(width: 8),
              _InfoChip(
                icon: Icons.star_outline,
                label: gym.averageRating > 0
                    ? gym.averageRating.toStringAsFixed(1)
                    : '—',
                scheme: scheme,
                theme: theme,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Audience & Amenities ─────────────────────────
          _DetailRow(
            label: 'الفئة المستهدفة',
            value: audienceLabel,
            theme: theme,
            scheme: scheme,
          ),

          if (gym.amenities.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: Text('الخدمات المتوفرة',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              alignment: WrapAlignment.end,
              children: gym.amenities
                  .map((a) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(amenityLabel(a),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onPrimaryContainer,
                              fontWeight: FontWeight.w600,
                            )),
                      ))
                  .toList(),
            ),
          ],

          const SizedBox(height: 16),

          // ── Subscription requests ────────────────────────
          OwnerGymSubscriptionRequestSection(
            key: ValueKey('sub-${gym.id}'),
            gymId: gym.id,
            api: api,
          ),

          const SizedBox(height: 12),

          // ── Photos ───────────────────────────────────────
          OwnerGymPhotosSection(
            key: ValueKey('photos-${gym.id}'),
            gymId: gym.id,
            api: api,
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.scheme,
    required this.theme,
  });
  final IconData icon;
  final String label;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.gold.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.gold.withValues(alpha: 0.18)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: AppTheme.gold),
            const SizedBox(height: 5),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: AppTheme.textSecondary,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.theme,
    required this.scheme,
  });
  final String label;
  final String value;
  final ThemeData theme;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary, // ink — 14:1 ✓
            )),
        const Spacer(),
        Text(label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: AppTheme.textSecondary, // #3D3852 — 9.2:1 ✓
            )),
      ],
    );
  }
}
