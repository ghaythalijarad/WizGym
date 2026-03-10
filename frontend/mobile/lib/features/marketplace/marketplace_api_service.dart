import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';
import '../../core/models/app_role.dart';
import 'marketplace_models.dart';

/// An API error that carries the HTTP status and a user-visible message.
class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;

  bool get isConflict => statusCode == 409;
  bool get isBadRequest => statusCode == 400;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

class MarketplaceApiService {
  MarketplaceApiService({required this.role, this.session})
      : _base = Uri.parse(_normalizeBaseUrl(AppConfig.apiBaseUrl));

  final AppRole role;
  final AuthSession? session;
  final Uri _base;

  Future<List<GymSummary>> fetchPublicGyms(
      {String? name, String? city, String? audience}) async {
    final params = <String>[];
    if (name != null && name.trim().isNotEmpty) {
      params.add('name=${Uri.encodeQueryComponent(name.trim())}');
    }
    if (city != null && city.trim().isNotEmpty) {
      params.add('city=${Uri.encodeQueryComponent(city.trim())}');
    }
    if (audience != null && audience.trim().isNotEmpty) {
      params.add('audience=${Uri.encodeQueryComponent(audience.trim())}');
    }
    final query = params.isEmpty ? '' : '?${params.join('&')}';
    final data = await _getJson('/gyms/public$query');

    if (data is! List) {
      throw const FormatException('Invalid gym list response');
    }

    return data
        .map((item) => GymSummary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<GymSummary>> fetchOwnerGyms() async {
    final data = await _getJson('/gyms/owner/mine');

    if (data is! List) {
      throw const FormatException('Invalid owner gyms response');
    }

    return data
        .map((item) => GymSummary.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<OwnerDashboardSummary> fetchOwnerDashboard() async {
    final data = await _getJson('/analytics/owner/dashboard');
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid owner dashboard response');
    }
    return OwnerDashboardSummary.fromJson(data);
  }

  Future<OwnerRetentionSummary> fetchOwnerRetention() async {
    final data = await _getJson('/analytics/owner/retention');
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid owner retention response');
    }
    return OwnerRetentionSummary.fromJson(data);
  }

  Future<GymDetail> fetchGymDetail(String gymId) async {
    final data = await _getJson('/gyms/$gymId/public');

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid gym details response');
    }

    return GymDetail.fromJson(data);
  }

  Future<List<GymTrainerItem>> fetchGymTrainers(String gymId) async {
    final data = await _getJson('/gyms/$gymId/trainers');

    if (data is! List) {
      throw const FormatException('Invalid gym trainers response');
    }

    return data
        .map((item) => GymTrainerItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<TrainerGymItem>> fetchTrainerGyms() async {
    final data = await _getJson('/trainers/me/gyms');

    if (data is! List) {
      throw const FormatException('Invalid trainer gyms response');
    }

    return data
        .map((item) => TrainerGymItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<List<TrainerClientItem>> fetchTrainerClients() async {
    final data = await _getJson('/trainers/me/clients');

    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid trainer clients response');
    }

    final clients = data['clients'];
    if (clients is! List) {
      return const [];
    }

    return clients
        .map((item) => TrainerClientItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> joinGymAsUser(String gymId, {String? planId}) {
    return _postJson('/gyms/$gymId/join', <String, dynamic>{
      if (planId != null) 'planId': planId,
    });
  }

  /// Fetch the current user's membership for a specific gym.
  /// Returns `null` if the user is not a member.
  Future<GymMemberItem?> fetchMyMembership(String gymId) async {
    final data = await _getJson('/gyms/$gymId/my-membership');
    if (data is! Map<String, dynamic>) return null;
    final membership = data['membership'];
    if (membership == null || membership is! Map<String, dynamic>) return null;
    return GymMemberItem.fromJson(membership);
  }

  /// Fetch ALL gym memberships for the current user (across all gyms).
  Future<List<MyGymMembership>> fetchMyGymMemberships() async {
    final data = await _getJson('/gyms/my-memberships');
    if (data is! Map<String, dynamic>) return const [];
    final list = data['memberships'];
    if (list is! List) return const [];
    return list
        .map((item) => MyGymMembership.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  /// Cancel a subscription plan that has not started yet.
  /// [target] can be 'NEXT' (queued plan) or 'CURRENT' (pending/not-started plan).
  Future<Map<String, dynamic>> cancelSubscription(String gymId,
      {String target = 'NEXT'}) {
    return _deleteJsonWithBody('/gyms/$gymId/my-membership', {
      'target': target,
    });
  }

  Future<Map<String, dynamic>> joinGymAsTrainer(String gymId) {
    return _postJson('/gyms/$gymId/trainers/join', <String, dynamic>{});
  }

  Future<Map<String, dynamic>> leaveGymAsTrainer(String gymId) {
    return _deleteJson('/gyms/$gymId/trainers/me');
  }

  Future<Map<String, dynamic>> createGym({
    required String name,
    required String city,
    String? description,
    String? coverImageUrl,
    String audience = 'MIXED',
    List<String> amenities = const [],
    List<Map<String, dynamic>> subscriptionPlans = const [],
  }) {
    return _postJson('/gyms', {
      'name': name.trim(),
      'city': city.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
      if (coverImageUrl != null && coverImageUrl.trim().isNotEmpty)
        'coverImageUrl': coverImageUrl.trim(),
      'audience': audience,
      'amenities': amenities,
      'subscriptionPlans': subscriptionPlans,
    });
  }

  Future<List<GymMemberItem>> fetchGymMembers(String gymId,
      {String? status}) async {
    final query =
        status != null ? '?status=${Uri.encodeQueryComponent(status)}' : '';
    final data = await _getJson('/gyms/$gymId/members$query');
    if (data is! List) {
      throw const FormatException('Invalid members response');
    }
    return data
        .map((item) => GymMemberItem.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> respondToMember({
    required String gymId,
    required String memberId,
    required String action, // 'APPROVE' | 'REJECT'
  }) {
    // URI-encode the memberId because user IDs may contain '#' (e.g. "USER#abc123")
    // which would be interpreted as a fragment separator if left unencoded.
    final encodedMemberId = Uri.encodeComponent(memberId);
    return _patchJson(
        '/gyms/$gymId/members/$encodedMemberId', {'action': action});
  }

  Future<Map<String, dynamic>> createSubscriptionPlan({
    required String gymId,
    required String title,
    required int durationMonths,
    required int price,
    String currency = 'IQD',
    String? description,
  }) {
    return _postJson('/gyms/$gymId/subscription-plans', {
      'title': title.trim(),
      'durationMonths': durationMonths,
      'price': price,
      'currency': currency,
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
  }

  Future<List<GymSubscriptionPlan>> fetchSubscriptionPlans(String gymId) async {
    final data = await _getJson('/gyms/$gymId/subscription-plans');
    if (data is! List) {
      throw const FormatException('Invalid subscription plans response');
    }
    return data
        .map((item) =>
            GymSubscriptionPlan.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> deleteSubscriptionPlan({
    required String gymId,
    required String planId,
  }) {
    return _deleteJson('/gyms/$gymId/subscription-plans/$planId');
  }

  Future<Map<String, dynamic>> updateSubscriptionPlan({
    required String gymId,
    required String planId,
    String? title,
    int? durationMonths,
    int? price,
    String? currency,
    String? description,
    bool? isActive,
  }) {
    return _patchJson('/gyms/$gymId/subscription-plans/$planId', {
      if (title != null) 'title': title.trim(),
      if (durationMonths != null) 'durationMonths': durationMonths,
      if (price != null) 'price': price,
      if (currency != null) 'currency': currency,
      if (description != null) 'description': description.trim(),
      if (isActive != null) 'isActive': isActive,
    });
  }

  Future<Map<String, dynamic>> hireTrainer(String gymId, String trainerId) {
    return _postJson('/gyms/$gymId/trainers/$trainerId/hire', <String, dynamic>{});
  }

  Future<Map<String, dynamic>> rateGym({
    required String gymId,
    required int rating,
    String? comment,
  }) {
    return _postJson('/gyms/$gymId/ratings', {
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
  }

  Future<Map<String, dynamic>> rateTrainer({
    required String trainerId,
    required String gymId,
    required int rating,
    String? comment,
  }) {
    return _postJson('/trainers/$trainerId/ratings', {
      'gymId': gymId,
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
  }

  Future<Map<String, dynamic>> createFacility({
    required String gymId,
    required String name,
    String? description,
  }) {
    return _postJson('/gyms/$gymId/facilities', {
      'name': name.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
    });
  }

  Future<Map<String, dynamic>> createProduct({
    required String gymId,
    required String title,
    String? description,
    int? price,
  }) {
    return _postJson('/gyms/$gymId/products', {
      'title': title.trim(),
      if (description != null && description.trim().isNotEmpty) 'description': description.trim(),
      if (price != null) 'price': price,
      'isActive': true,
    });
  }

  Future<Map<String, dynamic>> updateGymProfile({
    required String gymId,
    required String audience,
    required List<String> amenities,
    String? description,
  }) {
    return _patchJson('/gyms/$gymId/profile', {
      'audience': audience,
      'amenities': amenities,
      if (description != null) 'description': description.trim(),
    });
  }

  Future<dynamic> _getJson(String path) async {
    final response = await http.get(
      _resolve(path),
      headers: _headers,
    );

    return _decodeResponse(response);
  }

  Future<Map<String, dynamic>> _postJson(String path, Map<String, dynamic> payload) async {
    final response = await http.post(
      _resolve(path),
      headers: _headers,
      body: jsonEncode(payload),
    );

    final data = _decodeResponse(response);
    if (data is Map<String, dynamic>) {
      return data;
    }

    return {'data': data};
  }

  Future<Map<String, dynamic>> _patchJson(String path, Map<String, dynamic> payload) async {
    final response = await http.patch(
      _resolve(path),
      headers: _headers,
      body: jsonEncode(payload),
    );

    final data = _decodeResponse(response);
    if (data is Map<String, dynamic>) {
      return data;
    }

    return {'data': data};
  }

  Future<Map<String, dynamic>> _deleteJson(String path) async {
    final response = await http.delete(
      _resolve(path),
      headers: _headers,
    );

    final data = _decodeResponse(response);
    if (data is Map<String, dynamic>) {
      return data;
    }

    return {'data': data};
  }

  Future<Map<String, dynamic>> _deleteJsonWithBody(
      String path, Map<String, dynamic> payload) async {
    // http.delete doesn't support body, so use http.Request
    final request = http.Request('DELETE', _resolve(path));
    request.headers.addAll(_headers);
    request.body = jsonEncode(payload);
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);

    final data = _decodeResponse(response);
    if (data is Map<String, dynamic>) {
      return data;
    }

    return {'data': data};
  }

  Uri _resolve(String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return _base.resolve(normalized);
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (session?.token != null && session!.token.isNotEmpty)
          'Authorization': 'Bearer ${session!.token}',
        'x-user-role':
            (session?.role.apiValue ?? _roleHeader(role)).toUpperCase(),
        'x-user-id': session?.userId ?? _defaultUserId(role),
        'x-user-name': Uri.encodeComponent(
            (session?.displayName ?? _defaultUserName(role)).trim()),
      };

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // Try to extract a user-friendly message from the JSON body
      String msg = 'Request failed: ${response.statusCode}';
      try {
        final body = jsonDecode(response.body);
        if (body is Map && body['message'] is String) {
          msg = body['message'] as String;
        }
      } catch (_) {
        // Fallback to raw body
        if (response.body.isNotEmpty) msg = response.body;
      }
      throw ApiException(response.statusCode, msg);
    }

    return jsonDecode(response.body) as dynamic;
  }

  static String _roleHeader(AppRole role) {
    switch (role) {
      case AppRole.admin:
        return 'ADMIN';
      case AppRole.owner:
        return 'OWNER';
      case AppRole.trainer:
        return 'TRAINER';
      case AppRole.user:
      case AppRole.trainee:
        return 'USER';
    }
  }

  static String _defaultUserId(AppRole role) {
    switch (role) {
      case AppRole.admin:
        return 'platform-admin-1';
      case AppRole.owner:
        return 'owner-1003';
      case AppRole.trainer:
        return 'trainer-1';
      case AppRole.user:
      case AppRole.trainee:
        return 'user-1';
    }
  }

  static String _defaultUserName(AppRole role) {
    switch (role) {
      case AppRole.admin:
        return 'Platform Admin';
      case AppRole.owner:
        return 'Gym Owner';
      case AppRole.trainer:
        return 'Trainer';
      case AppRole.user:
      case AppRole.trainee:
        return 'Member';
    }
  }

  static String _normalizeBaseUrl(String baseUrl) {
    var url = baseUrl.trim();
    // Ensure trailing slash so Uri.resolve() keeps the full path prefix.
    if (!url.endsWith('/')) url = '$url/';
    return url;
  }
}
