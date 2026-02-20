import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/config/app_config.dart';
import 'admin_models.dart';

class AdminApiService {
  final Uri _base = Uri.parse(_normalizeBaseUrl(AppConfig.apiBaseUrl));

  Future<AdminDashboardSummary> fetchDashboard() async {
    final data = await _getJson('/admin/dashboard');
    return AdminDashboardSummary.fromJson(data);
  }

  Future<List<GymRequest>> fetchGyms() async {
    final data = await _getJson('/admin/gyms');

    if (data is! List) {
      throw const FormatException('Invalid gym list response');
    }

    return data
        .map((item) => GymRequest.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<GymRequest> approveGym(String gymId) async {
    final data = await _postJson('/admin/gyms/$gymId/approve', <String, dynamic>{});
    return GymRequest.fromJson(data);
  }

  Future<GymRequest> rejectGym(String gymId, {String? note}) async {
    final Map<String, dynamic> payload = note == null || note.trim().isEmpty
        ? <String, dynamic>{}
        : <String, dynamic>{'note': note.trim()};
    final data = await _postJson('/admin/gyms/$gymId/reject', payload);
    return GymRequest.fromJson(data);
  }

  Future<List<GymSubscription>> fetchSubscriptions() async {
    final data = await _getJson('/admin/subscriptions');

    if (data is! List) {
      throw const FormatException('Invalid subscription list response');
    }

    return data
        .map((item) => GymSubscription.fromJson(item as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<GymSubscription> updateSubscriptionStatus(
    String subscriptionId,
    SubscriptionStatus status,
  ) async {
    final data = await _patchJson('/admin/subscriptions/$subscriptionId/status', {
      'status': status.apiValue,
    });

    return GymSubscription.fromJson(data);
  }

  Future<dynamic> _getJson(String path) async {
    final response = await http.get(
      _resolve(path),
      headers: _headers,
    );

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

  Future<dynamic> _patchJson(String path, Map<String, dynamic> payload) async {
    final response = await http.patch(
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

  Map<String, String> get _headers => const {
        'Content-Type': 'application/json',
        'x-user-role': 'ADMIN',
        'x-user-id': 'platform-admin-1',
        'x-user-name': 'Platform Admin',
      };

  dynamic _decodeResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Request failed: ${response.statusCode} ${response.body}');
    }

    return jsonDecode(response.body) as dynamic;
  }

  static String _normalizeBaseUrl(String baseUrl) {
    return baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
  }
}
