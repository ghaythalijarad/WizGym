import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';
import '../../core/models/app_role.dart';

class PlansApiService {
  PlansApiService({required this.role, required this.session})
      : _base = Uri.parse(_normalizeBaseUrl(AppConfig.apiBaseUrl));

  final AppRole role;
  final AuthSession? session;
  final Uri _base;

  Future<List<PlanItem>> fetchMyPlans() async {
    final data = await _getJson('/plans/me');
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid plans response');
    }

    final plans = data['plans'];
    if (plans is! List) {
      return const [];
    }

    return plans
        .map((item) => PlanItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> createTraineePlan(String content) async {
    await _postJson('/plans/me', {'content': content.trim()});
  }

  Future<void> sendTrainerPlan({
    required String traineeUserId,
    required String content,
  }) async {
    await _postJson('/plans/trainer/send', {
      'traineeUserId': traineeUserId.trim(),
      'content': content.trim(),
    });
  }

  Future<List<TrainerClientSummary>> fetchTrainerClients() async {
    final data = await _getJson('/trainers/me/clients');
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid trainer clients response');
    }

    final clients = data['clients'];
    if (clients is! List) {
      return const [];
    }

    return clients
        .map((item) =>
            TrainerClientSummary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<SubscriptionRequest>> fetchSubscriptionRequests(
      {String? status}) async {
    final query =
        status != null ? '?status=${Uri.encodeQueryComponent(status)}' : '';
    final data = await _getJson('/trainers/me/subscription-requests$query');
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid subscription requests response');
    }
    final requests = data['requests'];
    if (requests is! List) return const [];
    return requests
        .map((item) =>
            SubscriptionRequest.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> respondToSubscriptionRequest({
    required String requestId,
    required String action, // 'APPROVE' | 'REJECT'
  }) async {
    await _patchJson(
        '/trainers/me/subscription-requests/$requestId', {'action': action});
  }

  Future<void> subscribeToTrainer({
    required String trainerId,
    String gymId = '',
  }) async {
    await _postJson('/trainers/$trainerId/subscribe', {'gymId': gymId});
  }

  Future<List<MySubscription>> fetchMySubscriptions() async {
    final data = await _getJson('/trainers/me/my-subscriptions');
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid subscriptions response');
    }
    final subs = data['subscriptions'];
    if (subs is! List) return const [];
    return subs
        .map((item) => MySubscription.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<dynamic> _patchJson(String path, Map<String, dynamic> payload) async {
    final response = await http.patch(
      _resolve(path),
      headers: _headers,
      body: jsonEncode(payload),
    );
    return _decodeResponse(response);
  }

  Future<dynamic> _getJson(String path) async {
    final response = await http.get(_resolve(path), headers: _headers);
    return _decodeResponse(response);
  }

  Future<dynamic> _postJson(String path, Map<String, dynamic> payload) async {
    final response = await http.post(
      _resolve(path),
      headers: _headers,
      body: jsonEncode(payload),
    );
    return _decodeResponse(response);
  }

  Uri _resolve(String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return _base.resolve(normalized);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (session?.token != null && session!.token.isNotEmpty)
          'Authorization': 'Bearer ${session!.token}',
        'x-user-role': (session?.role.apiValue ?? role.apiValue).toUpperCase(),
        'x-user-id': session?.userId ?? _defaultUserId(role),
        'x-user-name': _sanitizeHeaderValue(
            session?.displayName ?? _defaultUserName(role)),
      };

  static String _sanitizeHeaderValue(String value) {
    return value.replaceAll(RegExp(r'[^\x20-\x7E]'), '').trim();
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Request failed: ${response.statusCode} ${response.body}');
    }
    return jsonDecode(response.body);
  }

  static String _defaultUserId(AppRole role) {
    switch (role) {
      case AppRole.owner:
        return 'acc-owner-1';
      case AppRole.trainer:
        return 'acc-trainer-1';
      case AppRole.trainee:
      case AppRole.user:
        return 'acc-trainee-1';
      case AppRole.admin:
        return 'acc-admin-1';
    }
  }

  static String _defaultUserName(AppRole role) {
    switch (role) {
      case AppRole.owner:
        return 'Demo Owner';
      case AppRole.trainer:
        return 'Demo Trainer';
      case AppRole.trainee:
      case AppRole.user:
        return 'Demo Trainee';
      case AppRole.admin:
        return 'Demo Admin';
    }
  }

  static String _normalizeBaseUrl(String baseUrl) {
    return baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  }
}

class PlanItem {
  const PlanItem({
    required this.id,
    required this.type,
    required this.content,
    required this.createdByRole,
    required this.createdByName,
    required this.traineeName,
    required this.createdAt,
    this.trainerName,
  });

  final String id;
  final String type;
  final String content;
  final String createdByRole;
  final String createdByName;
  final String traineeName;
  final String createdAt;
  final String? trainerName;

  bool get isFromTrainer => type == 'TRAINER_TO_TRAINEE';

  factory PlanItem.fromJson(Map<String, dynamic> json) {
    return PlanItem(
      id: (json['id'] ?? '').toString(),
      type: (json['type'] ?? '').toString(),
      content: (json['content'] ?? '').toString(),
      createdByRole: (json['createdByRole'] ?? '').toString(),
      createdByName: (json['createdByName'] ?? '').toString(),
      traineeName: (json['traineeName'] ?? '').toString(),
      trainerName: json['trainerName']?.toString(),
      createdAt: _toHumanDate((json['createdAt'] ?? '').toString()),
    );
  }

  static String _toHumanDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      return raw;
    }
    final local = parsed.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class TrainerClientSummary {
  const TrainerClientSummary({
    required this.id,
    required this.name,
    required this.gymId,
  });

  final String id;
  final String name;
  final String gymId;

  factory TrainerClientSummary.fromJson(Map<String, dynamic> json) {
    return TrainerClientSummary(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      gymId: (json['gymId'] ?? '').toString(),
    );
  }
}

class SubscriptionRequest {
  const SubscriptionRequest({
    required this.requestId,
    required this.clientId,
    required this.clientName,
    required this.gymId,
    required this.status,
    required this.requestedAt,
    this.respondedAt,
  });

  final String requestId;
  final String clientId;
  final String clientName;
  final String gymId;
  final String status; // PENDING | APPROVED | REJECTED
  final String requestedAt;
  final String? respondedAt;

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';

  factory SubscriptionRequest.fromJson(Map<String, dynamic> json) {
    return SubscriptionRequest(
      requestId: (json['requestId'] ?? '').toString(),
      clientId: (json['clientId'] ?? '').toString(),
      clientName: (json['clientName'] ?? '').toString(),
      gymId: (json['gymId'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      requestedAt: _toHumanDate((json['requestedAt'] ?? '').toString()),
      respondedAt: json['respondedAt'] != null
          ? _toHumanDate(json['respondedAt'].toString())
          : null,
    );
  }

  static String _toHumanDate(String raw) {
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    final local = parsed.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }
}

class MySubscription {
  const MySubscription({
    required this.trainerId,
    required this.status,
    required this.requestedAt,
  });

  final String trainerId;
  final String status; // PENDING | APPROVED | REJECTED
  final String requestedAt;

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';

  factory MySubscription.fromJson(Map<String, dynamic> json) {
    return MySubscription(
      trainerId: (json['trainerId'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      requestedAt: (json['requestedAt'] ?? '').toString(),
    );
  }
}
