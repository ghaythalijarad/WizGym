import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/auth/auth_session.dart';
import '../../core/config/app_config.dart';
import '../../core/models/app_role.dart';
import 'marketplace_models.dart';

class MarketplaceApiService {
  MarketplaceApiService({required this.role, this.session})
      : _base = Uri.parse(_normalizeBaseUrl(AppConfig.apiBaseUrl));

  final AppRole role;
  final AuthSession? session;
  final Uri _base;

  Future<List<GymSummary>> fetchPublicGyms({String? city, String? audience}) async {
    final params = <String>[];
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

  Future<Map<String, dynamic>> joinGymAsTrainer(String gymId) {
    return _postJson('/gyms/$gymId/trainers/join', <String, dynamic>{});
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
    return _patchJson('/gyms/$gymId/members/$memberId', {'action': action});
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
        'x-user-name': session?.displayName ?? _defaultUserName(role),
      };

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed: ${response.statusCode} ${response.body}');
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
    return baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  }
}
