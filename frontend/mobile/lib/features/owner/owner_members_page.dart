import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/models/app_role.dart';
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

  /// Direct state lists for optimistic UI
  List<GymMemberItem> _pendingMembers = [];
  List<GymMemberItem> _activeMembers = [];
  bool _loadingMembers = false;
  String? _membersError;
  bool _initialLoadDone = false;

  /// planId → GymSubscriptionPlan for title lookup
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
    // Load subscription plans for plan-title lookup
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
      // ── Optimistic UI: move from pending → active ──
      if (mounted) {
        setState(() {
          _pendingMembers.removeWhere((m) => m.userId == member.userId);
          _activeMembers.insert(0, member);
        });
      }
      _showMsg('تمت الموافقة على ${member.userName}');
      // Background re-sync after a short delay
      Future.delayed(const Duration(seconds: 1), _fetchMembers);
    } catch (_) {
      _showMsg('تعذرت الموافقة');
    }
  }

  Future<void> _rejectMember(GymMemberItem member) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض العضو'),
        content: Text('هل تريد رفض طلب ${member.userName}؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء')),
          FilledButton(
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
      // ── Optimistic UI: remove from pending ──
      if (mounted) {
        setState(() {
          _pendingMembers.removeWhere((m) => m.userId == member.userId);
        });
      }
      _showMsg('تم رفض طلب ${member.userName}');
      // Background re-sync after a short delay
      Future.delayed(const Duration(seconds: 1), _fetchMembers);
    } catch (_) {
      _showMsg('تعذر الرفض');
    }
  }

  void _showMsg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Gym selector
        FutureBuilder<List<GymSummary>>(
          future: _gymsFuture,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              );
            }
            final gyms = snap.data ?? [];
            if (gyms.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('لا توجد نوادي مملوكة لك حالياً.'),
              );
            }
            _selectedGymId ??= gyms.first.id;
            if (!_initialLoadDone) {
              _initialLoadDone = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_selectedGymId != null) {
                  _onGymSelected(_selectedGymId!);
                }
              });
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: _selectedGymId,
                decoration: const InputDecoration(labelText: 'اختر النادي'),
                items: gyms
                    .map((g) => DropdownMenuItem(
                        value: g.id, child: Text('${g.name} (${g.city})')))
                    .toList(growable: false),
                onChanged: (v) {
                  if (v != null) _onGymSelected(v);
                },
              ),
            );
          },
        ),
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'بانتظار الموافقة'),
            Tab(text: 'الأعضاء الحاليون'),
          ],
        ),
        Expanded(
          child: _loadingMembers
              ? const Center(child: CircularProgressIndicator())
              : _membersError != null
                  ? Center(child: Text(_membersError!))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _MemberList(
                          members: _pendingMembers,
                          emptyText: 'لا توجد طلبات انضمام معلقة',
                          showActions: true,
                          onApprove: _approveMember,
                          onReject: _rejectMember,
                          plansMap: _plansMap,
                        ),
                        _MemberList(
                          members: _activeMembers,
                          emptyText: 'لا يوجد أعضاء حاليون',
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

// ─────────────────────────────────────────────────────────────────────
// _MemberList — now takes a direct List instead of a Future
// ─────────────────────────────────────────────────────────────────────

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.members,
    required this.emptyText,
    this.showActions = false,
    this.onApprove,
    this.onReject,
    this.plansMap = const {},
  });

  final List<GymMemberItem> members;
  final String emptyText;
  final bool showActions;
  final void Function(GymMemberItem)? onApprove;
  final void Function(GymMemberItem)? onReject;
  final Map<String, GymSubscriptionPlan> plansMap;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(emptyText, style: Theme.of(context).textTheme.bodyLarge),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final m = members[index];
        // ...existing plan/expiry/nextPlan label logic...
        final plan =
            m.selectedPlanId != null ? plansMap[m.selectedPlanId] : null;
        final String? planLabel;
        if (plan != null) {
          planLabel =
              '${plan.title} (${plan.durationMonths} ${plan.durationMonths == 1 ? 'شهر' : 'أشهر'} — ${plan.price} ${plan.currency})';
        } else if (m.selectedPlanTitle != null) {
          final dur = m.selectedPlanDurationMonths;
          planLabel = dur != null
              ? '${m.selectedPlanTitle} ($dur ${dur == 1 ? 'شهر' : 'أشهر'})'
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
              ? '$npTitle ($npDur ${npDur == 1 ? 'شهر' : 'أشهر'})${npStart != null ? ' — تبدأ $npStart' : ''}'
              : '$npTitle${npStart != null ? ' — تبدأ $npStart' : ''}';
        } else {
          nextPlanLabel = null;
        }

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
                        m.userName.isNotEmpty
                            ? m.userName[0].toUpperCase()
                            : '؟',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(m.userName.isNotEmpty ? m.userName : 'عضو',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text('انضم: ${_shortDate(m.joinedAt)}',
                              style: Theme.of(context).textTheme.bodySmall),
                          if (planLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.card_membership,
                                      size: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      planLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (expiryLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(
                                    expired
                                        ? Icons.warning_amber_rounded
                                        : Icons.event_available,
                                    size: 14,
                                    color: expired ? Colors.red : Colors.green,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    expired
                                        ? 'انتهى: $expiryLabel'
                                        : 'ينتهي: $expiryLabel',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color:
                                              expired ? Colors.red : Colors.green,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                  if (expired) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.red.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'منتهي',
                                        style: TextStyle(
                                          color: Colors.red,
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          if (nextPlanLabel != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Row(
                                children: [
                                  Icon(Icons.update,
                                      size: 14,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .tertiary),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      'التالي: $nextPlanLabel',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .tertiary,
                                          ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _StatusChip(status: m.status),
                        if (m.isActive && expired)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'اشتراك منتهي',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
                if (showActions) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => onReject?.call(m),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('رفض'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () => onApprove?.call(m),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('موافقة'),
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

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status.toUpperCase()) {
      case 'ACTIVE':
        color = Colors.green;
        label = 'فعّال';
        break;
      case 'REJECTED':
        color = Colors.red;
        label = 'مرفوض';
        break;
      default:
        color = Colors.orange;
        label = 'معلق';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}
