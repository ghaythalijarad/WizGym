import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/auth/auth_events.dart';
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

  Future<TrainerPublicProfile> fetchTrainerPublicProfile(
      String trainerId) async {
    final encoded = Uri.encodeComponent(trainerId);
    final data = await _getJson('/trainers/$encoded/public');
    if (data is! Map<String, dynamic>) {
      throw const FormatException('Invalid trainer profile response');
    }
    return TrainerPublicProfile.fromJson(data);
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

  Future<Map<String, dynamic>> joinGymAsUser(
    String gymId, {
    String? planId,
    bool? forceJoin,
  }) {
    return _postJson('/gyms/$gymId/join', <String, dynamic>{
      if (planId != null) 'planId': planId,
      if (forceJoin == true) 'forceJoin': true,
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
    Map<String, dynamic>? openingHours,
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
      if (openingHours != null) 'openingHours': openingHours,
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
    required double rating,
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
    required double rating,
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
    Map<String, dynamic>? openingHours,
  }) {
    return _patchJson('/gyms/$gymId/profile', {
      'audience': audience,
      'amenities': amenities,
      if (description != null) 'description': description.trim(),
      if (openingHours != null) 'openingHours': openingHours,
    });
  }

  // Returns a short-lived URL for viewing a photo when the bucket is private.
  Future<String> fetchGymPhotoViewUrl(
    String gymId, {
    required String photoId,
  }) async {
    final data = await _getJson('/gyms/$gymId/photos/$photoId/view-url');
    if (data is! Map) {
      throw const FormatException('Invalid gym photo view-url response');
    }
    final url = data['url'];
    if (url is! String || url.isEmpty) {
      throw const FormatException('Invalid gym photo view-url payload');
    }
    return url;
  }

  Future<List<GymPhotoItem>> fetchGymPhotos(String gymId) async {
    final data = await _getJson('/gyms/$gymId/photos');
    final map = data is Map ? data : null;
    if (map == null) {
      throw const FormatException('Invalid gym photos response');
    }
    final photos = map['photos'];
    if (photos is! List) return const <GymPhotoItem>[];
    return photos
        .whereType<Map>()
        .map((p) => GymPhotoItem.fromJson(p.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<PresignUploadResponse> presignGymPhotoUpload(
    String gymId, {
    required String contentType,
  }) async {
    final data = await _postJson('/gyms/$gymId/photos/presign', {
      'contentType': contentType,
    });

    // `_postJson` always returns a Map<String, dynamic>.
    return PresignUploadResponse.fromJson(data);
  }

  Future<Map<String, dynamic>> createGymPhoto(String gymId,
      {required String url}) {
    return _postJson('/gyms/$gymId/photos', {'url': url});
  }

  Future<Map<String, dynamic>> deleteGymPhoto(
    String gymId, {
    required String photoId,
  }) {
    return _deleteJson('/gyms/$gymId/photos/$photoId');
  }

  // ── Platform subscription activation (owner) ─────────────────────────

  Future<List<PlatformSubscriptionPlan>>
      fetchPlatformSubscriptionPlans() async {
    final data = await _getJson('/subscriptions/plans');
    if (data is! Map) {
      throw const FormatException('Invalid subscription plans response');
    }
    final plans = data['plans'];
    if (plans is! List) return const <PlatformSubscriptionPlan>[];
    return plans
        .whereType<Map>()
        .map(
            (p) => PlatformSubscriptionPlan.fromJson(p.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<PresignUploadResponse> presignSubscriptionProofUpload(
    String gymId, {
    required String contentType,
  }) async {
    final data = await _postJson('/gyms/$gymId/subscription-requests/presign', {
      'contentType': contentType,
    });
    return PresignUploadResponse.fromJson(data);
  }

  Future<CreateSubscriptionRequestResponse> createGymSubscriptionRequest(
    String gymId, {
    required String planId,
    required String screenshotUrl,
    String? screenshotObjectKey,
  }) async {
    final data = await _postJson('/gyms/$gymId/subscription-requests', {
      'planId': planId,
      'screenshotUrl': screenshotUrl,
      if (screenshotObjectKey != null && screenshotObjectKey.trim().isNotEmpty)
        'screenshotObjectKey': screenshotObjectKey.trim(),
    });
    return CreateSubscriptionRequestResponse.fromJson(data);
  }

  Future<List<GymSubscriptionRequestItem>> fetchMyGymSubscriptionRequests(
    String gymId,
  ) async {
    final data = await _getJson('/gyms/$gymId/subscription-requests/mine');
    if (data is! Map) {
      throw const FormatException('Invalid subscription requests response');
    }
    final list = data['requests'];
    if (list is! List) return const <GymSubscriptionRequestItem>[];
    return list
        .whereType<Map>()
        .map((r) =>
            GymSubscriptionRequestItem.fromJson(r.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<PresignUploadResponse> presignTrainerCertificateUpload({
    required String contentType,
  }) async {
    final data = await _postJson('/trainers/me/certificates/presign', {
      'contentType': contentType,
    });
    return PresignUploadResponse.fromJson(data);
  }

  Future<List<TrainerCertificateItem>> fetchTrainerCertificates(
    String trainerId,
  ) async {
    final encoded = Uri.encodeComponent(trainerId);
    final data = await _getJson('/trainers/$encoded/certificates');
    if (data is! Map) {
      throw const FormatException('Invalid trainer certificates response');
    }
    final list = data['certificates'];
    if (list is! List) return const <TrainerCertificateItem>[];
    return list
        .whereType<Map>()
        .map((e) => TrainerCertificateItem.fromJson(e.cast<String, dynamic>()))
        .toList(growable: false);
  }

  Future<List<Map<String, dynamic>>> fetchMyTrainerCertificatesRaw() async {
    final data = await _getJson('/trainers/me/certificates');
    if (data is! Map) {
      throw const FormatException('Invalid my trainer certificates response');
    }
    final list = data['certificates'];
    if (list is! List) return const <Map<String, dynamic>>[];
    return list
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  }

  Future<Map<String, dynamic>> createTrainerCertificate({
    required String name,
    required int year,
    required String imageUrl,
    String? objectKey,
    String? description,
  }) {
    return _postJson('/trainers/me/certificates', {
      'name': name.trim(),
      'year': year,
      'imageUrl': imageUrl.trim(),
      if (objectKey != null && objectKey.trim().isNotEmpty)
        'objectKey': objectKey.trim(),
      if (description != null && description.trim().isNotEmpty)
        'description': description.trim(),
    });
  }

  Future<Map<String, dynamic>> deleteTrainerCertificate({
    required String certificateId,
  }) {
    return _deleteJson(
        '/trainers/me/certificates/${Uri.encodeComponent(certificateId)}');
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
    if (response.statusCode == 401) {
      AuthEvents.emitUnauthorized();
      throw ApiException(401, 'Unauthorized — session expired');
    }
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

class GymPhotoItem {
  const GymPhotoItem(
      {required this.photoId, required this.url, this.uploadedAt});

  final String photoId;
  final String url;
  final String? uploadedAt;

  factory GymPhotoItem.fromJson(Map<String, dynamic> json) {
    return GymPhotoItem(
      photoId: (json['photoId'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      uploadedAt: json['uploadedAt']?.toString(),
    );
  }
}

class PresignUploadResponse {
  const PresignUploadResponse({
    required this.uploadUrl,
    required this.url,
    required this.objectKey,
    this.expiresIn,
  });

  final String uploadUrl;
  final String url;
  final String objectKey;
  final int? expiresIn;

  factory PresignUploadResponse.fromJson(Map<String, dynamic> json) {
    return PresignUploadResponse(
      uploadUrl: (json['uploadUrl'] ?? '').toString(),
      url: (json['url'] ?? '').toString(),
      objectKey: (json['objectKey'] ?? '').toString(),
      expiresIn:
          json['expiresIn'] is num ? (json['expiresIn'] as num).toInt() : null,
    );
  }
}

class PlatformSubscriptionPlan {
  const PlatformSubscriptionPlan({
    required this.planId,
    required this.durationMonths,
    required this.price,
    required this.currency,
  });

  final String planId;
  final int durationMonths;
  final int price;
  final String currency;

  factory PlatformSubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return PlatformSubscriptionPlan(
      planId: (json['planId'] ?? '').toString(),
      durationMonths: (json['durationMonths'] is num)
          ? (json['durationMonths'] as num).toInt()
          : int.tryParse((json['durationMonths'] ?? '1').toString()) ?? 1,
      price: (json['price'] is num)
          ? (json['price'] as num).toInt()
          : int.tryParse((json['price'] ?? '0').toString()) ?? 0,
      currency: (json['currency'] ?? 'IQD').toString(),
    );
  }

  String get labelAr => durationMonths == 12
      ? 'سنة'
      : durationMonths == 9
          ? '٩ أشهر'
          : durationMonths == 6
              ? '٦ أشهر'
              : durationMonths == 3
                  ? '٣ أشهر'
                  : durationMonths == 2
                      ? 'شهران'
                      : 'شهر';
}

class CreateSubscriptionRequestResponse {
  const CreateSubscriptionRequestResponse(
      {required this.requestId, required this.status});

  final String requestId;
  final String status;

  factory CreateSubscriptionRequestResponse.fromJson(
      Map<String, dynamic> json) {
    return CreateSubscriptionRequestResponse(
      requestId: (json['requestId'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
    );
  }
}

class GymSubscriptionRequestItem {
  const GymSubscriptionRequestItem({
    required this.requestId,
    required this.status,
    required this.planId,
    required this.durationMonths,
    required this.price,
    required this.currency,
    required this.transferToPhone,
    required this.screenshotUrl,
    required this.createdAt,
    this.reviewedAt,
    this.note,
  });

  final String requestId;
  final String status;
  final String planId;
  final int durationMonths;
  final int price;
  final String currency;
  final String transferToPhone;
  final String screenshotUrl;
  final String createdAt;
  final String? reviewedAt;
  final String? note;

  factory GymSubscriptionRequestItem.fromJson(Map<String, dynamic> json) {
    return GymSubscriptionRequestItem(
      requestId: (json['requestId'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      planId: (json['planId'] ?? '').toString(),
      durationMonths: (json['durationMonths'] is num)
          ? (json['durationMonths'] as num).toInt()
          : int.tryParse((json['durationMonths'] ?? '1').toString()) ?? 1,
      price: (json['price'] is num)
          ? (json['price'] as num).toInt()
          : int.tryParse((json['price'] ?? '0').toString()) ?? 0,
      currency: (json['currency'] ?? 'IQD').toString(),
      transferToPhone: (json['transferToPhone'] ?? '07831367435').toString(),
      screenshotUrl: (json['screenshotUrl'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
      reviewedAt: json['reviewedAt']?.toString(),
      note: json['note']?.toString(),
    );
  }
}
