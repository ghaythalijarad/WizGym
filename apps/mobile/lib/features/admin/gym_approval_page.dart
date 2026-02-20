import 'package:flutter/material.dart';

import 'admin_api_service.dart';
import 'admin_models.dart';

class GymApprovalPage extends StatefulWidget {
  const GymApprovalPage({super.key});

  @override
  State<GymApprovalPage> createState() => _GymApprovalPageState();
}

class _GymApprovalPageState extends State<GymApprovalPage> {
  final AdminApiService _api = AdminApiService();
  late Future<List<GymRequest>> _requestsFuture;

  @override
  void initState() {
    super.initState();
    _requestsFuture = _api.fetchGyms();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refresh,
      child: FutureBuilder<List<GymRequest>>(
        future: _requestsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            return _ErrorState(onRetry: _reload);
          }

          final requests = snapshot.data ?? const <GymRequest>[];

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              Text('اعتماد النوادي', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'راجع طلبات الانضمام ووافق أو ارفض مباشرة من لوحة المدير.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              ...requests.map((item) => _buildRequestCard(context, item)),
            ],
          );
        },
      ),
    );
  }

  Widget _buildRequestCard(BuildContext context, GymRequest request) {
    final canReview = request.status == GymApprovalStatus.pending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    request.gymName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                _StatusChip(
                  label: _gymStatusLabel(request.status),
                  color: _gymStatusColor(request.status),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text('المالك: ${request.ownerName}'),
            Text('المدينة: ${request.city}'),
            Text('تاريخ الطلب: ${request.requestedDate}'),
            if (request.reviewNote != null && request.reviewNote!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('ملاحظة: ${request.reviewNote}'),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: canReview ? () => _reject(request.id) : null,
                    child: const Text('رفض'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canReview ? () => _approve(request.id) : null,
                    child: const Text('اعتماد'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(String gymId) async {
    try {
      await _api.approveGym(gymId);
      _reload();
      _showResult('تم اعتماد النادي بنجاح');
    } catch (_) {
      _showResult('فشل اعتماد النادي');
    }
  }

  Future<void> _reject(String gymId) async {
    try {
      await _api.rejectGym(gymId, note: 'Missing compliance documents');
      _reload();
      _showResult('تم رفض طلب النادي');
    } catch (_) {
      _showResult('فشل رفض الطلب');
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _requestsFuture = _api.fetchGyms();
    });

    await _requestsFuture;
  }

  void _reload() {
    setState(() {
      _requestsFuture = _api.fetchGyms();
    });
  }

  void _showResult(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _gymStatusLabel(GymApprovalStatus status) {
    switch (status) {
      case GymApprovalStatus.pending:
        return 'معلق';
      case GymApprovalStatus.approved:
        return 'معتمد';
      case GymApprovalStatus.rejected:
        return 'مرفوض';
    }
  }

  Color _gymStatusColor(GymApprovalStatus status) {
    switch (status) {
      case GymApprovalStatus.pending:
        return const Color(0xFFB45309);
      case GymApprovalStatus.approved:
        return const Color(0xFF047857);
      case GymApprovalStatus.rejected:
        return const Color(0xFFB91C1C);
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.error_outline, size: 42, color: Colors.red.shade700),
        const SizedBox(height: 10),
        const Text('تعذر تحميل طلبات النوادي', textAlign: TextAlign.center),
        const SizedBox(height: 12),
        ElevatedButton(onPressed: onRetry, child: const Text('إعادة المحاولة')),
      ],
    );
  }
}
