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

  late Future<List<GymMemberItem>> _pendingFuture;
  late Future<List<GymMemberItem>> _activeFuture;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _api = MarketplaceApiService(role: AppRole.owner, session: widget.session);
    _gymsFuture = _api.fetchOwnerGyms();
    _pendingFuture = Future.value(const []);
    _activeFuture = Future.value(const []);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _onGymSelected(String gymId) {
    setState(() {
      _selectedGymId = gymId;
      _pendingFuture = _api.fetchGymMembers(gymId, status: 'PENDING');
      _activeFuture = _api.fetchGymMembers(gymId, status: 'ACTIVE');
    });
  }

  void _reloadMembers() {
    if (_selectedGymId == null) return;
    setState(() {
      _pendingFuture = _api.fetchGymMembers(_selectedGymId!, status: 'PENDING');
      _activeFuture = _api.fetchGymMembers(_selectedGymId!, status: 'ACTIVE');
    });
  }

  Future<void> _approveMember(GymMemberItem member) async {
    try {
      await _api.respondToMember(
        gymId: member.gymId,
        memberId: member.userId,
        action: 'APPROVE',
      );
      _showMsg('تمت الموافقة على ${member.userName}');
      _reloadMembers();
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
      _showMsg('تم رفض طلب ${member.userName}');
      _reloadMembers();
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
          child: TabBarView(
            controller: _tabController,
            children: [
              _MemberList(
                future: _pendingFuture,
                emptyText: 'لا توجد طلبات انضمام معلقة',
                showActions: true,
                onApprove: _approveMember,
                onReject: _rejectMember,
              ),
              _MemberList(
                future: _activeFuture,
                emptyText: 'لا يوجد أعضاء حاليون',
                showActions: false,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({
    required this.future,
    required this.emptyText,
    this.showActions = false,
    this.onApprove,
    this.onReject,
  });

  final Future<List<GymMemberItem>> future;
  final String emptyText;
  final bool showActions;
  final void Function(GymMemberItem)? onApprove;
  final void Function(GymMemberItem)? onReject;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<GymMemberItem>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return const Center(child: Text('تعذر تحميل الأعضاء'));
        }
        final members = snap.data ?? [];
        if (members.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child:
                  Text(emptyText, style: Theme.of(context).textTheme.bodyLarge),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: members.length,
          itemBuilder: (context, index) {
            final m = members[index];
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
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              Text('انضم: ${_shortDate(m.joinedAt)}',
                                  style: Theme.of(context).textTheme.bodySmall),
                              if (m.selectedPlanId != null)
                                Text('الخطة: ${m.selectedPlanId}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        _StatusChip(status: m.status),
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
