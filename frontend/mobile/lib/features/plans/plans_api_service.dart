import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/auth/auth_events.dart';
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

  Future<void> deleteTraineePlan(String planId) async {
    final response = await http.delete(
      _resolve('/plans/me/${Uri.encodeComponent(planId)}'),
      headers: _headers,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Failed to delete plan: ${response.statusCode} ${response.body}');
    }
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
        '/trainers/me/subscription-requests/${Uri.encodeComponent(requestId)}',
        {'action': action});
  }

  Future<void> subscribeToTrainer({
    required String trainerId,
    String gymId = '',
    String? planId,
  }) async {
    final encoded = Uri.encodeComponent(trainerId);
    await _postJson('/trainers/$encoded/subscribe', {
      'gymId': gymId,
      if (planId != null) 'planId': planId,
    });
  }

  /// Cancel / withdraw a PENDING trainer subscription request.
  /// The backend rejects this if the subscription is already APPROVED.
  Future<void> cancelTrainerSubscription({required String trainerId}) async {
    final encoded = Uri.encodeComponent(trainerId);
    await _deleteJson('/trainers/$encoded/subscribe');
  }

  // ── Trainer subscription plans ──────────────────────────────────────────────

  Future<List<TrainerSubscriptionPlan>> fetchMySubscriptionPlans() async {
    final data = await _getJson('/trainers/me/subscription-plans');
    if (data is! Map<String, dynamic>) return const [];
    final plans = data['plans'];
    if (plans is! List) return const [];
    return plans
        .map((p) => TrainerSubscriptionPlan.fromJson(p as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<TrainerSubscriptionPlan> createSubscriptionPlan({
    required String name,
    required double price,
    required int durationMonths,
    String description = '',
  }) async {
    final data = await _postJson('/trainers/me/subscription-plans', {
      'title': name,
      'price': price,
      'durationMonths': durationMonths,
      'description': description,
    });
    if (data is Map<String, dynamic>) {
      return TrainerSubscriptionPlan(
        planId: data['planId']?.toString() ?? '',
        title: name,
        price: price,
        durationMonths: durationMonths,
        description: description,
      );
    }
    throw const FormatException('Invalid plan response');
  }

  Future<void> deleteSubscriptionPlan(String planId) async {
    await _deleteJson(
        '/trainers/me/subscription-plans/${Uri.encodeComponent(planId)}');
  }

  /// Public — trainee fetches trainer's available plans before subscribing.
  Future<List<TrainerSubscriptionPlan>> fetchTrainerSubscriptionPlans(
      String trainerId) async {
    final encoded = Uri.encodeComponent(trainerId);
    final data = await _getJson('/trainers/$encoded/subscription-plans');
    if (data is! Map<String, dynamic>) return const [];
    final plans = data['plans'];
    if (plans is! List) return const [];
    return plans
        .map((p) => TrainerSubscriptionPlan.fromJson(p as Map<String, dynamic>))
        .toList(growable: false);
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

  Future<dynamic> _deleteJson(String path) async {
    final response = await http.delete(_resolve(path), headers: _headers);
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
    // URI-encode so Arabic/non-ASCII names survive HTTP header restrictions
    return Uri.encodeComponent(value.trim());
  }

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode == 401) {
      AuthEvents.emitUnauthorized();
      throw Exception('Unauthorized — session expired');
    }
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
    this.planId,
    this.planName,
    this.planPrice,
    this.durationMonths,
    this.expiresAt,
  });

  final String requestId;
  final String clientId;
  final String clientName;
  final String gymId;
  final String status; // PENDING | APPROVED | REJECTED
  final String requestedAt;
  final String? respondedAt;
  final String? planId;
  final String? planName;
  final double? planPrice;
  final int? durationMonths;
  final String? expiresAt;

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
      planId: json['planId']?.toString(),
      planName: json['planName']?.toString(),
      planPrice: json['planPrice'] != null
          ? (json['planPrice'] as num).toDouble()
          : null,
      durationMonths: json['durationMonths'] != null
          ? (json['durationMonths'] as num).toInt()
          : null,
      expiresAt: json['expiresAt'] != null
          ? _toHumanDate(json['expiresAt'].toString())
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
    this.planId,
    this.planName,
    this.planPrice,
    this.durationMonths,
    this.expiresAt,
  });

  final String trainerId;
  final String status; // PENDING | APPROVED | REJECTED
  final String requestedAt;
  final String? planId;
  final String? planName;
  final double? planPrice;
  final int? durationMonths;
  final String? expiresAt;

  bool get isPending => status == 'PENDING';
  bool get isApproved => status == 'APPROVED';

  factory MySubscription.fromJson(Map<String, dynamic> json) {
    return MySubscription(
      trainerId: (json['trainerId'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      requestedAt: (json['requestedAt'] ?? '').toString(),
      planId: json['planId']?.toString(),
      planName: json['planName']?.toString(),
      planPrice: json['planPrice'] != null
          ? (json['planPrice'] as num).toDouble()
          : null,
      durationMonths: json['durationMonths'] != null
          ? (json['durationMonths'] as num).toInt()
          : null,
      expiresAt: json['expiresAt']?.toString(),
    );
  }
}

// ── Trainer subscription plan (unified with GymSubscriptionPlan schema) ──────

class TrainerSubscriptionPlan {
  const TrainerSubscriptionPlan({
    required this.planId,
    required this.title,
    required this.price,
    required this.durationMonths,
    this.currency = 'IQD',
    this.description = '',
    this.isActive = true,
  });

  final String planId;
  final String title;
  final double price;
  final int durationMonths;
  final String currency;
  final String description;
  final bool isActive;

  /// Back-compat getter so old code using `.name` still works.
  String get name => title;

  factory TrainerSubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return TrainerSubscriptionPlan(
      planId: (json['planId'] ?? '').toString(),
      // Prefer "title" (unified), fall back to "name" (old data)
      title: (json['title'] ?? json['name'] ?? '').toString(),
      price: (json['price'] as num? ?? 0).toDouble(),
      durationMonths: (json['durationMonths'] as num? ?? 1).toInt(),
      currency: (json['currency'] ?? 'IQD').toString(),
      description: (json['description'] ?? '').toString(),
      isActive: json['isActive'] != false,
    );
  }

  String get durationLabel {
    if (durationMonths == 1) return 'شهر واحد';
    if (durationMonths == 2) return 'شهران';
    if (durationMonths <= 10) return '$durationMonths أشهر';
    return '$durationMonths شهراً';
  }
}
