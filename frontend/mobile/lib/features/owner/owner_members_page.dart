import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../marketplace/marketplace_api_service.dart';
import '../marketplace/marketplace_models.dart';

class OwnerMembersPage extends StatefulWidget {
  const OwnerMembersPage({super.key, this.session});

  final AuthSession? session;

  @override
  State<OwnerMembersPage> createState() => _OwnerMembersPageState();
}

class _OwnerMembersPageState extends State<OwnerMembersPage>
    with SingleTickerProviderStateMixin {
  late final MarketplaceApiService _api;
  late final TabController _tabController;
  late Future<List<GymSummary>> _gymsFuture;
  String? _selectedGymId;

  List<GymMemberItem> _pendingMembers = [];
  List<GymMemberItem> _activeMembers = [];
  bool _loadingMembers = false;
  String? _membersError;
  bool _initialLoadDone = false;

  Map<String, GymSubscriptionPlan> _plansMap = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
    _gymsFuture = _api.fetchOwnerGyms();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onGymSelected(String gymId) {
    _selectedGymId = gymId;
    _plansMap = {};
    _fetchMembers();
    _api.fetchSubscriptionPlans(gymId).then((plans) {
      if (mounted) {
        setState(() {
          _plansMap = {for (final p in plans) p.planId: p};
        });
      }
    }).catchError((_) {});
  }

  Future<void> _fetchMembers() async {
    if (_selectedGymId == null) return;
    setState(() {
      _loadingMembers = true;
      _membersError = null;
    });
    try {
      final results = await Future.wait([
        _api.fetchGymMembers(_selectedGymId!, status: 'PENDING'),
        _api.fetchGymMembers(_selectedGymId!, status: 'ACTIVE'),
      ]);
      if (mounted) {
        setState(() {
          _pendingMembers = results[0];
          _activeMembers = results[1];
          _loadingMembers = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingMembers = false;
          _membersError = 'تعذر تحميل الأعضاء';
        });
      }
    }
  }

  Future<void> _approveMember(GymMemberItem member) async {
    try {
      await _api.respondToMember(
        gymId: member.gymId,
        memberId: member.userId,
        action: 'APPROVE',
      );
      if (mounted) {
        setState(() {
          _pendingMembers.removeWhere((m) => m.userId == member.userId);
          _activeMembers.insert(0, member);
        });
      }
      _showMsg('تمت الموافقة على ${member.userName}');
      Future.delayed(const Duration(seconds: 1), _fetchMembers);
    } catch (_) {
      _showMsg('تعذرت الموافقة');
    }
  }

  Future<void> _rejectMember(GymMemberItem member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E35),
        title: const Text('رفض العضو',
            style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('هل تريد رفض طلب ${member.userName}؟',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء',
                  style: TextStyle(color: AppTheme.textSecondary))),
          FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('رفض')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _api.respondToMember(
        gymId: member.gymId,
        memberId: member.userId,
        action: 'REJECT',
      );
      if (mounted) {
        setState(() {
          _pendingMembers.removeWhere((m) => m.userId == member.userId);
        });
      }
      _showMsg('تم رفض طلب ${member.userName}');
      Future.delayed(const Duration(seconds: 1), _fetchMembers);
    } catch (_) {
      _showMsg('تعذر الرفض');
    }
  }

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: const Color(0xFF1E1E35),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Gold section header ─────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.gold,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'إدارة الأعضاء',
                style: TextStyle(
                  color: AppTheme.gold,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // ── Gym selector ────────────────────────────────────────────
        FutureBuilder<List<GymSummary>>(
          future: _gymsFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: LinearProgressIndicator(color: AppTheme.gold),
              );
            }
            final gyms = snap.data ?? [];
            if (gyms.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(20),
                child: Text('لا توجد نوادي مملوكة لك حالياً.',
                    style: TextStyle(color: AppTheme.textSecondary)),
              );
            }
            _selectedGymId ??= gyms.first.id;
            if (!_initialLoadDone) {
              _initialLoadDone = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_selectedGymId != null) _onGymSelected(_selectedGymId!);
              });
            }
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF16162A),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: AppTheme.gold.withValues(alpha: 0.25)),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedGymId,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF1E1E35),
                    style: const TextStyle(
                        color: AppTheme.textPrimary, fontSize: 14),
                    iconEnabledColor: AppTheme.gold,
                    items: gyms
                        .map((g) => DropdownMenuItem(
                            value: g.id,
                            child: Text('${g.name} — ${g.city}',
                                style: const TextStyle(
                                    color: AppTheme.textPrimary))))
                        .toList(growable: false),
                    onChanged: (v) {
                      if (v != null) _onGymSelected(v);
                    },
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),

        // ── Gold TabBar ──────────────────────────────────────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF16162A),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.gold.withValues(alpha: 0.18)),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppTheme.gold.withValues(alpha: 0.5)),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: AppTheme.gold,
            unselectedLabelColor: AppTheme.textMuted,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.hourglass_top_rounded, size: 15),
                    const SizedBox(width: 6),
                    const Text('بانتظار الموافقة'),
                    if (_pendingMembers.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: _pendingMembers.length),
                    ],
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.people_alt_rounded, size: 15),
                    const SizedBox(width: 6),
                    const Text('الأعضاء الحاليون'),
                    if (_activeMembers.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      _CountBadge(count: _activeMembers.length, active: true),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ── Content ──────────────────────────────────────────────────
        Expanded(
          child: _loadingMembers
              ? const Center(
                  child: CircularProgressIndicator(color: AppTheme.gold))
              : _membersError != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline,
                              color: Colors.redAccent, size: 40),
                          const SizedBox(height: 8),
                          Text(_membersError!,
                              style: const TextStyle(
                                  color: AppTheme.textSecondary)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _fetchMembers,
                            icon: const Icon(Icons.refresh),
                            label: const Text('إعادة المحاولة'),
                            style: OutlinedButton.styleFrom(
                                foregroundColor: AppTheme.gold,
                                side: const BorderSide(
                                    color: AppTheme.gold, width: 1.5)),
                          ),
                        ],
                      ),
                    )
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _MemberList(
                          members: _pendingMembers,
                          emptyText: 'لا توجد طلبات انضمام معلقة',
                          emptyIcon: Icons.hourglass_empty_rounded,
                          showActions: true,
                          onApprove: _approveMember,
                          onReject: _rejectMember,
                          plansMap: _plansMap,
                        ),
                        _MemberList(
                          members: _activeMembers,
                          emptyText: 'لا يوجد أعضاء حاليون',
                          emptyIcon: Icons.people_outline_rounded,
                          showActions: false,
                          plansMap: _plansMap,
                        ),
                      ],
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CountBadge
// ─────────────────────────────────────────────────────────────────────────────
class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count, this.active = false});
  final int count;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: active
            ? AppTheme.gold.withValues(alpha: 0.2)
            : Colors.amber.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: active ? AppTheme.gold : Colors.amber.shade300,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _MemberList
// ─────────────────────────────────────────────────────────────────────────────
class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.members,
    required this.emptyText,
    required this.emptyIcon,
    this.showActions = false,
    this.onApprove,
    this.onReject,
    this.plansMap = const {},
  });

  final List<GymMemberItem> members;
  final String emptyText;
  final IconData emptyIcon;
  final bool showActions;
  final void Function(GymMemberItem)? onApprove;
  final void Function(GymMemberItem)? onReject;
  final Map<String, GymSubscriptionPlan> plansMap;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(emptyIcon,
                  size: 42, color: AppTheme.gold.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 14),
            Text(emptyText,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 15)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 24),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final m = members[index];
        final plan =
            m.selectedPlanId != null ? plansMap[m.selectedPlanId] : null;

        final String? planLabel;
        if (plan != null) {
          planLabel =
              '${plan.title} · ${plan.durationMonths} ${plan.durationMonths == 1 ? 'شهر' : 'أشهر'} · ${plan.price} ${plan.currency}';
        } else if (m.selectedPlanTitle != null) {
          final dur = m.selectedPlanDurationMonths;
          planLabel = dur != null
              ? '${m.selectedPlanTitle} · $dur ${dur == 1 ? 'شهر' : 'أشهر'}'
              : m.selectedPlanTitle!;
        } else if (m.selectedPlanId != null) {
          planLabel = 'خطة: ${m.selectedPlanId}';
        } else {
          planLabel = null;
        }

        final bool expired = m.isExpired;
        final String? expiryLabel = m.subscriptionExpiresAt != null
            ? _shortDate(m.subscriptionExpiresAt!)
            : null;

        final String? nextPlanLabel;
        if (m.hasNextPlan) {
          final npTitle = m.nextPlanTitle ?? 'خطة تالية';
          final npDur = m.nextPlanDurationMonths;
          final npStart = m.nextPlanStartsAt != null
              ? _shortDate(m.nextPlanStartsAt!)
              : null;
          nextPlanLabel = npDur != null
              ? '$npTitle · $npDur ${npDur == 1 ? 'شهر' : 'أشهر'}${npStart != null ? ' — تبدأ $npStart' : ''}'
              : '$npTitle${npStart != null ? ' — تبدأ $npStart' : ''}';
        } else {
          nextPlanLabel = null;
        }

        final initials =
            m.userName.isNotEmpty ? m.userName[0].toUpperCase() : '؟';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF16162A),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: showActions
                  ? AppTheme.gold.withValues(alpha: 0.35)
                  : AppTheme.gold.withValues(alpha: 0.12),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Avatar + name row ────────────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Gold ring avatar
                    Container(
                      width: 44,
                      height: 44,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [AppTheme.gold, AppTheme.goldDeep],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: const TextStyle(
                            color: AppTheme.textOnGold,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.userName.isNotEmpty ? m.userName : 'عضو',
                            style: const TextStyle(
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 11, color: AppTheme.textMuted),
                              const SizedBox(width: 3),
                              Text('انضم: ${_shortDate(m.joinedAt)}',
                                  style: const TextStyle(
                                      color: AppTheme.textMuted, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    _StatusChip(status: m.status, expired: expired),
                  ],
                ),

                // ── Plan info chips ──────────────────────────────────
                if (planLabel != null ||
                    expiryLabel != null ||
                    nextPlanLabel != null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (planLabel != null)
                        _InfoPill(
                          icon: Icons.card_membership_rounded,
                          label: planLabel,
                          color: AppTheme.gold,
                        ),
                      if (expiryLabel != null)
                        _InfoPill(
                          icon: expired
                              ? Icons.warning_amber_rounded
                              : Icons.event_available_rounded,
                          label: expired
                              ? 'انتهى: $expiryLabel'
                              : 'ينتهي: $expiryLabel',
                          color: expired
                              ? Colors.redAccent
                              : const Color(0xFF34D399),
                        ),
                      if (nextPlanLabel != null)
                        _InfoPill(
                          icon: Icons.update_rounded,
                          label: 'التالي: $nextPlanLabel',
                          color: AppTheme.goldLight,
                        ),
                    ],
                  ),
                ],

                // ── Action buttons ───────────────────────────────────
                if (showActions) ...[
                  const SizedBox(height: 12),
                  const Divider(color: Color(0xFF2A2A45), height: 1),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onReject?.call(m),
                          icon: const Icon(Icons.close_rounded, size: 16),
                          label: const Text('رفض'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: BorderSide(
                                color: Colors.redAccent.withValues(alpha: 0.5)),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => onApprove?.call(m),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('قبول'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.gold,
                            foregroundColor: AppTheme.textOnGold,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _shortDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _InfoPill
// ─────────────────────────────────────────────────────────────────────────────
class _InfoPill extends StatelessWidget {
  const _InfoPill(
      {required this.icon, required this.label, required this.color});
  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                  color: color, fontSize: 11, fontWeight: FontWeight.w600),
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
// _StatusChip
// ─────────────────────────────────────────────────────────────────────────────
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, this.expired = false});
  final String status;
  final bool expired;

  @override
  Widget build(BuildContext context) {
    late Color color;
    late String label;
    late IconData icon;

    if (expired && status.toUpperCase() == 'ACTIVE') {
      color = Colors.redAccent;
      label = 'منتهي';
      icon = Icons.timer_off_rounded;
    } else {
      switch (status.toUpperCase()) {
        case 'ACTIVE':
          color = const Color(0xFF34D399);
          label = 'فعّال';
          icon = Icons.check_circle_rounded;
          break;
        case 'REJECTED':
          color = Colors.redAccent;
          label = 'مرفوض';
          icon = Icons.cancel_rounded;
          break;
        default:
          color = Colors.amber;
          label = 'معلق';
          icon = Icons.hourglass_top_rounded;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12)),
        ],
      ),
    );
  }
}
