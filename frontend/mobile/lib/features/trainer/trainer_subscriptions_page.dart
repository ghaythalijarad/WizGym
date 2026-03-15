import 'package:flutter/material.dart';

import '../../core/auth/auth_session.dart';
import '../../core/auth/auth_session_store.dart';
import '../../core/models/app_role.dart';
import '../../core/theme/app_theme.dart';
import '../plans/plans_api_service.dart';

class TrainerSubscriptionsPage extends StatefulWidget {
  const TrainerSubscriptionsPage({super.key, this.session});

  final AuthSession? session;

  @override
  State<TrainerSubscriptionsPage> createState() =>
      _TrainerSubscriptionsPageState();
}

class _TrainerSubscriptionsPageState extends State<TrainerSubscriptionsPage>
    with SingleTickerProviderStateMixin {
  final AuthSessionStore _sessionStore = AuthSessionStore();
  AuthSession? _session;

  late TabController _tabController;
  late Future<List<SubscriptionRequest>> _pendingFuture;
  late Future<List<SubscriptionRequest>> _approvedFuture;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _tabController = TabController(length: 2, vsync: this);
    _pendingFuture = _loadRequests('PENDING');
    _approvedFuture = _loadRequests('APPROVED');
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<PlansApiService> _api() async {
    _session ??= await _sessionStore.load();
    return PlansApiService(role: AppRole.trainer, session: _session);
  }

  Future<List<SubscriptionRequest>> _loadRequests(String status) async {
    final api = await _api();
    return api.fetchSubscriptionRequests(status: status);
  }

  void _reload() {
    setState(() {
      _pendingFuture = _loadRequests('PENDING');
      _approvedFuture = _loadRequests('APPROVED');
    });
  }

  Future<void> _respond(String requestId, String action) async {
    try {
      final api = await _api();
      await api.respondToSubscriptionRequest(
          requestId: requestId, action: action);
      _showMessage(action == 'APPROVE' ? 'تم قبول الطلب ✓' : 'تم رفض الطلب');
      _reload();
    } catch (e) {
      _showMessage('حدث خطأ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('طلبات الاشتراك'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _reload,
            tooltip: 'تحديث',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'معلقة', icon: Icon(Icons.pending_outlined)),
            Tab(text: 'مقبولة', icon: Icon(Icons.check_circle_outline)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _RequestsList(
            future: _pendingFuture,
            emptyMessage: 'لا توجد طلبات معلقة',
            onReload: _reload,
            itemBuilder: (req) => _PendingCard(
              request: req,
              onApprove: () => _respond(req.requestId, 'APPROVE'),
              onReject: () => _respond(req.requestId, 'REJECT'),
              scheme: scheme,
            ),
          ),
          _RequestsList(
            future: _approvedFuture,
            emptyMessage: 'لا يوجد متدربون مقبولون بعد',
            onReload: _reload,
            itemBuilder: (req) => _ApprovedCard(request: req, scheme: scheme),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

// ── Generic list with FutureBuilder ──────────────────────────────────────────

class _RequestsList extends StatelessWidget {
  const _RequestsList({
    required this.future,
    required this.emptyMessage,
    required this.onReload,
    required this.itemBuilder,
  });

  final Future<List<SubscriptionRequest>> future;
  final String emptyMessage;
  final VoidCallback onReload;
  final Widget Function(SubscriptionRequest) itemBuilder;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => onReload(),
      child: FutureBuilder<List<SubscriptionRequest>>(
        future: future,
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
                Text('تعذر التحميل: ${snapshot.error}',
                    textAlign: TextAlign.center),
                const SizedBox(height: 12),
                ElevatedButton(
                    onPressed: onReload, child: const Text('إعادة المحاولة')),
              ],
            );
          }
          final items = snapshot.data ?? const [];
          if (items.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(32),
              children: [
                const Icon(Icons.inbox_outlined, size: 52, color: Colors.grey),
                const SizedBox(height: 14),
                Text(emptyMessage,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)),
              ],
            );
          }
          return ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
            itemCount: items.length,
            itemBuilder: (_, i) => itemBuilder(items[i]),
          );
        },
      ),
    );
  }
}

// ── Pending request card with approve / reject ────────────────────────────────

class _PendingCard extends StatelessWidget {
  const _PendingCard({
    required this.request,
    required this.onApprove,
    required this.onReject,
    required this.scheme,
  });

  final SubscriptionRequest request;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: AppTheme.cardLavender.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      AppTheme.cardLavender.withValues(alpha: 0.18),
                  child: Text(
                    request.clientName.isNotEmpty
                        ? request.clientName[0].toUpperCase()
                        : '؟',
                    style: const TextStyle(
                        color: AppTheme.cardLavender,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        request.clientName.isNotEmpty
                            ? request.clientName
                            : 'متدرب',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (request.gymId.isNotEmpty)
                        Text('النادي: ${request.gymId}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text('معلق',
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'طلب في: ${request.requestedAt}',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textSecondary),
            ),
            if (request.planName != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.card_membership,
                      size: 14, color: AppTheme.gold),
                  const SizedBox(width: 4),
                  Text(
                    request.planName!,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.gold,
                        fontWeight: FontWeight.w600),
                  ),
                  if (request.planPrice != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      '${request.planPrice} د.ع',
                      style: const TextStyle(
                          fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReject,
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('رفض'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(
                          color: scheme.error.withValues(alpha: 0.6)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onApprove,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('قبول'),
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
      ),
    );
  }
}

// ── Approved client card ──────────────────────────────────────────────────────

class _ApprovedCard extends StatelessWidget {
  const _ApprovedCard({required this.request, required this.scheme});

  final SubscriptionRequest request;
  final ColorScheme scheme;

  bool _isExpired(String iso) {
    try {
      return DateTime.parse(iso).isBefore(DateTime.now());
    } catch (_) {
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.gold.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: AppTheme.gold.withValues(alpha: 0.18),
              child: Text(
                request.clientName.isNotEmpty
                    ? request.clientName[0].toUpperCase()
                    : '؟',
                style: const TextStyle(
                    color: AppTheme.gold, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.clientName.isNotEmpty
                        ? request.clientName
                        : 'متدرب',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  if (request.gymId.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('النادي: ${request.gymId}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                  if (request.respondedAt != null) ...[
                    const SizedBox(height: 2),
                    Text('قُبل في: ${request.respondedAt}',
                        style: const TextStyle(
                            fontSize: 12, color: AppTheme.textSecondary)),
                  ],
                  if (request.planName != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.card_membership,
                            size: 14, color: AppTheme.gold),
                        const SizedBox(width: 4),
                        Text(
                          request.planName!,
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.gold,
                              fontWeight: FontWeight.w600),
                        ),
                        if (request.planPrice != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${request.planPrice} د.ع',
                            style: const TextStyle(
                                fontSize: 12, color: AppTheme.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (request.expiresAt != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          _isExpired(request.expiresAt!)
                              ? Icons.event_busy
                              : Icons.event_available,
                          size: 14,
                          color: _isExpired(request.expiresAt!)
                              ? Colors.red.shade400
                              : Colors.green.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isExpired(request.expiresAt!)
                              ? 'انتهى: ${request.expiresAt}'
                              : 'ينتهي: ${request.expiresAt}',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isExpired(request.expiresAt!)
                                ? Colors.red.shade400
                                : Colors.green.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text('مقبول',
                  style: TextStyle(
                      color: AppTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
