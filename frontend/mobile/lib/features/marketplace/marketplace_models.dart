/// Represents a single day's opening and closing time.
class DayHours {
  const DayHours({required this.open, required this.close});

  final String open; // e.g. "06:00"
  final String close; // e.g. "22:00"

  factory DayHours.fromJson(Map<String, dynamic> json) {
    return DayHours(
      open: (json['open'] ?? '').toString(),
      close: (json['close'] ?? '').toString(),
    );
  }

  Map<String, String> toJson() => {'open': open, 'close': close};

  bool get isEmpty => open.isEmpty && close.isEmpty;
}

/// 7 days of the week keys used across the app (Arabic gym culture starts Saturday).
const List<String> kWeekDayKeys = [
  'saturday',
  'sunday',
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
];

const Map<String, String> kWeekDayLabelsAr = {
  'saturday': 'السبت',
  'sunday': 'الأحد',
  'monday': 'الاثنين',
  'tuesday': 'الثلاثاء',
  'wednesday': 'الأربعاء',
  'thursday': 'الخميس',
  'friday': 'الجمعة',
};

Map<String, DayHours>? _parseOpeningHours(dynamic raw) {
  if (raw == null || raw is! Map) return null;
  final result = <String, DayHours>{};
  for (final entry in raw.entries) {
    final key = entry.key.toString().toLowerCase();
    if (entry.value is Map) {
      final dh =
          DayHours.fromJson((entry.value as Map).cast<String, dynamic>());
      if (!dh.isEmpty) result[key] = dh;
    }
  }
  return result.isEmpty ? null : result;
}

Map<String, dynamic>? openingHoursToJson(Map<String, DayHours>? hours) {
  if (hours == null || hours.isEmpty) return null;
  return hours.map((k, v) => MapEntry(k, v.toJson()));
}

class GymSummary {
  GymSummary({
    required this.id,
    required this.name,
    required this.city,
    required this.description,
    required this.coverImageUrl,
    required this.audience,
    required this.amenities,
    required this.membersCount,
    required this.trainersCount,
    required this.averageRating,
    this.status = 'ACTIVE',
    this.photos = const [],
    this.photoViewUrls = const [],
    this.openingHours,
  });

  final String id;
  final String name;
  final String city;
  final String? description;
  final String? coverImageUrl;
  final String audience;
  final List<String> amenities;
  final int membersCount;
  final int trainersCount;
  final double averageRating;
  final String status;
  final List<String> photos;
  final List<String> photoViewUrls;
  final Map<String, DayHours>? openingHours;

  factory GymSummary.fromJson(Map<String, dynamic> json) {
    final viewRaw = json['photoViewUrls'];
    final viewUrls = viewRaw is List
        ? viewRaw
            .map((e) => e is Map ? e['url'] : null)
            .whereType<Object>()
            .map((e) => e.toString())
            .where((u) => u.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    return GymSummary(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      description: json['description']?.toString(),
      coverImageUrl: json['coverImageUrl']?.toString(),
      audience: (json['audience'] ?? 'MIXED').toString(),
      amenities: _toStringList(json['amenities']),
      membersCount: _toInt(json['membersCount']),
      trainersCount: _toInt(json['trainersCount']),
      averageRating: _toDouble(json['averageRating']),
      status: (json['status'] ?? 'ACTIVE').toString(),
      photos: _toStringList(json['photos']),
      photoViewUrls: viewUrls,
      openingHours: _parseOpeningHours(json['openingHours']),
    );
  }
}

class GymDetail {
  GymDetail({
    required this.id,
    required this.name,
    required this.city,
    required this.description,
    required this.coverImageUrl,
    required this.audience,
    required this.amenities,
    required this.ownerName,
    required this.averageRating,
    required this.facilities,
    required this.products,
    this.subscriptionPlans = const [],
    this.photoViewUrls = const [],
    this.openingHours,
  });

  final String id;
  final String name;
  final String city;
  final String? description;
  final String? coverImageUrl;
  final String audience;
  final List<String> amenities;
  final String ownerName;
  final double averageRating;
  final List<GymFacilityItem> facilities;
  final List<GymProductItem> products;
  final List<GymSubscriptionPlan> subscriptionPlans;
  final List<String> photoViewUrls;
  final Map<String, DayHours>? openingHours;

  factory GymDetail.fromJson(Map<String, dynamic> json) {
    final facilitiesRaw = json['facilities'];
    final productsRaw = json['products'];
    final plansRaw = json['subscriptionPlans'];
    final viewRaw = json['photoViewUrls'];
    final viewUrls = viewRaw is List
        ? viewRaw
            .map((e) => e is Map ? e['url'] : null)
            .whereType<Object>()
            .map((e) => e.toString())
            .where((u) => u.trim().isNotEmpty)
            .toList(growable: false)
        : const <String>[];

    return GymDetail(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      description: json['description']?.toString(),
      coverImageUrl: json['coverImageUrl']?.toString(),
      audience: (json['audience'] ?? 'MIXED').toString(),
      amenities: _toStringList(json['amenities']),
      ownerName: (json['ownerName'] ?? '').toString(),
      averageRating: _toDouble(json['averageRating']),
      photoViewUrls: viewUrls,
      facilities: facilitiesRaw is List
          ? facilitiesRaw
              .map((item) => GymFacilityItem.fromJson(item as Map<String, dynamic>))
              .toList(growable: false)
          : const [],
      products: productsRaw is List
          ? productsRaw
              .map((item) => GymProductItem.fromJson(item as Map<String, dynamic>))
              .toList(growable: false)
          : const [],
      subscriptionPlans: plansRaw is List
          ? plansRaw
              .map((item) =>
                  GymSubscriptionPlan.fromJson(item as Map<String, dynamic>))
              .toList(growable: false)
          : const [],
      openingHours: _parseOpeningHours(json['openingHours']),
    );
  }
}

class GymTrainerItem {
  GymTrainerItem({
    required this.trainerId,
    required this.displayName,
    required this.activeClients,
    required this.averageRating,
    required this.hiredByRequester,
  });

  final String trainerId;
  final String displayName;
  final int activeClients;
  final double averageRating;
  final bool hiredByRequester;

  factory GymTrainerItem.fromJson(Map<String, dynamic> json) {
    return GymTrainerItem(
      trainerId: (json['trainerId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      activeClients: _toInt(json['activeClients']),
      averageRating: _toDouble(json['averageRating']),
      hiredByRequester: json['hiredByRequester'] == true,
    );
  }
}

class GymFacilityItem {
  GymFacilityItem({
    required this.id,
    required this.name,
    this.description,
  });

  final String id;
  final String name;
  final String? description;

  factory GymFacilityItem.fromJson(Map<String, dynamic> json) {
    return GymFacilityItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      description: json['description']?.toString(),
    );
  }
}

class GymProductItem {
  GymProductItem({
    required this.id,
    required this.title,
    this.description,
    this.price,
  });

  final String id;
  final String title;
  final String? description;
  final int? price;

  factory GymProductItem.fromJson(Map<String, dynamic> json) {
    final rawPrice = json['price'];

    return GymProductItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: json['description']?.toString(),
      price: rawPrice == null ? null : _toInt(rawPrice),
    );
  }
}

class TrainerGymItem {
  TrainerGymItem({
    required this.gymId,
    required this.gymName,
    required this.city,
    required this.activeClients,
    required this.averageRating,
  });

  final String gymId;
  final String gymName;
  final String city;
  final int activeClients;
  final double averageRating;

  factory TrainerGymItem.fromJson(Map<String, dynamic> json) {
    return TrainerGymItem(
      gymId: (json['gymId'] ?? '').toString(),
      gymName: (json['gymName'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      activeClients: _toInt(json['activeClients']),
      averageRating: _toDouble(json['averageRating']),
    );
  }
}

class TrainerCertificateImage {
  TrainerCertificateImage({
    required this.url,
    required this.presigned,
    required this.expiresIn,
  });

  final String url;
  final bool presigned;
  final int? expiresIn;

  factory TrainerCertificateImage.fromJson(Map<String, dynamic> json) {
    return TrainerCertificateImage(
      url: (json['url'] ?? '').toString(),
      presigned: json['presigned'] == true,
      expiresIn: json['expiresIn'] == null ? null : _toInt(json['expiresIn']),
    );
  }
}

class TrainerCertificateItem {
  TrainerCertificateItem({
    required this.id,
    required this.name,
    required this.year,
    required this.description,
    required this.image,
  });

  final String id;
  final String name;
  final int? year;
  final String description;
  final TrainerCertificateImage image;

  factory TrainerCertificateItem.fromJson(Map<String, dynamic> json) {
    return TrainerCertificateItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      year: json['year'] == null ? null : _toInt(json['year']),
      description: (json['description'] ?? '').toString(),
      image: TrainerCertificateImage.fromJson(
          (json['image'] as Map?)?.cast<String, dynamic>() ?? const {}),
    );
  }
}

class TrainerClientItem {
  TrainerClientItem({
    required this.id,
    required this.name,
    required this.gymId,
  });

  final String id;
  final String name;
  final String gymId;

  factory TrainerClientItem.fromJson(Map<String, dynamic> json) {
    return TrainerClientItem(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      gymId: (json['gymId'] ?? '').toString(),
    );
  }
}

class OwnerDashboardSummary {
  OwnerDashboardSummary({
    required this.totalMembers,
    required this.totalTrainers,
    required this.totalGyms,
    required this.occupancyRate,
    required this.averageRating,
  });

  final int totalMembers;
  final int totalTrainers;
  final int totalGyms;
  final double occupancyRate;
  final double averageRating;

  factory OwnerDashboardSummary.fromJson(Map<String, dynamic> json) {
    return OwnerDashboardSummary(
      totalMembers: _toInt(json['totalMembers']),
      totalTrainers: _toInt(json['totalTrainers']),
      totalGyms: _toInt(json['totalGyms']),
      occupancyRate: _toDouble(json['occupancyRate']),
      averageRating: _toDouble(json['averageRating']),
    );
  }
}

class OwnerRetentionSummary {
  OwnerRetentionSummary({
    required this.month,
    required this.retentionPercent,
    required this.churnPercent,
    required this.predictedAtRisk,
  });

  final String month;
  final double retentionPercent;
  final double churnPercent;
  final int predictedAtRisk;

  factory OwnerRetentionSummary.fromJson(Map<String, dynamic> json) {
    return OwnerRetentionSummary(
      month: (json['month'] ?? '').toString(),
      retentionPercent: _toDouble(json['retentionPercent']),
      churnPercent: _toDouble(json['churnPercent']),
      predictedAtRisk: _toInt(json['predictedAtRisk']),
    );
  }
}

class GymSubscriptionPlan {
  GymSubscriptionPlan({
    required this.planId,
    required this.title,
    required this.durationMonths,
    required this.price,
    required this.currency,
    this.description,
    this.isActive = true,
  });

  final String planId;
  final String title;
  final int durationMonths;
  final int price;
  final String currency;
  final String? description;
  final bool isActive;

  factory GymSubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return GymSubscriptionPlan(
      planId: (json['planId'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      durationMonths: _toInt(json['durationMonths']),
      price: _toInt(json['price']),
      currency: (json['currency'] ?? 'IQD').toString(),
      description: json['description']?.toString(),
      isActive: json['isActive'] != false,
    );
  }
}

class GymMemberItem {
  GymMemberItem({
    required this.userId,
    required this.userName,
    required this.gymId,
    required this.status,
    required this.joinedAt,
    this.selectedPlanId,
    this.selectedPlanTitle,
    this.selectedPlanDurationMonths,
    this.subscriptionStartsAt,
    this.subscriptionExpiresAt,
    this.nextPlanId,
    this.nextPlanTitle,
    this.nextPlanDurationMonths,
    this.nextPlanStartsAt,
    this.nextPlanExpiresAt,
  });

  final String userId;
  final String userName;
  final String gymId;
  final String status; // PENDING | ACTIVE | REJECTED
  final String joinedAt;
  final String? selectedPlanId;
  final String? selectedPlanTitle;
  final int? selectedPlanDurationMonths;
  final String? subscriptionStartsAt;
  final String? subscriptionExpiresAt;
  // Queued next plan (starts after current expires)
  final String? nextPlanId;
  final String? nextPlanTitle;
  final int? nextPlanDurationMonths;
  final String? nextPlanStartsAt;
  final String? nextPlanExpiresAt;

  bool get isPending => status == 'PENDING';
  bool get isActive => status == 'ACTIVE';

  /// Whether the current subscription has expired.
  bool get isExpired {
    if (subscriptionExpiresAt == null) return false;
    final exp = DateTime.tryParse(subscriptionExpiresAt!);
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  /// Whether the member has a queued next plan.
  bool get hasNextPlan => nextPlanId != null && nextPlanId!.isNotEmpty;

  factory GymMemberItem.fromJson(Map<String, dynamic> json) {
    return GymMemberItem(
      userId: (json['userId'] ?? '').toString(),
      userName: (json['userName'] ?? '').toString(),
      gymId: (json['gymId'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      joinedAt: (json['joinedAt'] ?? '').toString(),
      selectedPlanId: json['selectedPlanId']?.toString(),
      selectedPlanTitle: json['selectedPlanTitle']?.toString(),
      selectedPlanDurationMonths: json['selectedPlanDurationMonths'] != null
          ? _toInt(json['selectedPlanDurationMonths'])
          : null,
      subscriptionStartsAt: json['subscriptionStartsAt']?.toString(),
      subscriptionExpiresAt: json['subscriptionExpiresAt']?.toString(),
      nextPlanId: json['nextPlanId']?.toString(),
      nextPlanTitle: json['nextPlanTitle']?.toString(),
      nextPlanDurationMonths: json['nextPlanDurationMonths'] != null
          ? _toInt(json['nextPlanDurationMonths'])
          : null,
      nextPlanStartsAt: json['nextPlanStartsAt']?.toString(),
      nextPlanExpiresAt: json['nextPlanExpiresAt']?.toString(),
    );
  }
}

/// A user's gym membership summary (returned by GET /gyms/my-memberships).
class MyGymMembership {
  const MyGymMembership({
    required this.gymId,
    required this.gymName,
    required this.gymCity,
    required this.status,
    this.joinedAt,
    this.selectedPlanId,
    this.selectedPlanTitle,
    this.selectedPlanDurationMonths,
    this.subscriptionStartsAt,
    this.subscriptionExpiresAt,
    this.nextPlanId,
    this.nextPlanTitle,
    this.nextPlanStartsAt,
    this.nextPlanExpiresAt,
  });

  final String gymId;
  final String gymName;
  final String gymCity;
  final String status; // PENDING, ACTIVE, REJECTED
  final String? joinedAt;
  final String? selectedPlanId;
  final String? selectedPlanTitle;
  final int? selectedPlanDurationMonths;
  final String? subscriptionStartsAt;
  final String? subscriptionExpiresAt;
  final String? nextPlanId;
  final String? nextPlanTitle;
  final String? nextPlanStartsAt;
  final String? nextPlanExpiresAt;

  bool get isActive => status == 'ACTIVE';
  bool get isPending => status == 'PENDING';

  bool get isExpired {
    if (subscriptionExpiresAt == null) return false;
    final exp = DateTime.tryParse(subscriptionExpiresAt!);
    if (exp == null) return false;
    return DateTime.now().isAfter(exp);
  }

  factory MyGymMembership.fromJson(Map<String, dynamic> json) {
    return MyGymMembership(
      gymId: (json['gymId'] ?? '').toString(),
      gymName: (json['gymName'] ?? '').toString(),
      gymCity: (json['gymCity'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      joinedAt: json['joinedAt']?.toString(),
      selectedPlanId: json['selectedPlanId']?.toString(),
      selectedPlanTitle: json['selectedPlanTitle']?.toString(),
      selectedPlanDurationMonths: json['selectedPlanDurationMonths'] != null
          ? _toInt(json['selectedPlanDurationMonths'])
          : null,
      subscriptionStartsAt: json['subscriptionStartsAt']?.toString(),
      subscriptionExpiresAt: json['subscriptionExpiresAt']?.toString(),
      nextPlanId: json['nextPlanId']?.toString(),
      nextPlanTitle: json['nextPlanTitle']?.toString(),
      nextPlanStartsAt: json['nextPlanStartsAt']?.toString(),
      nextPlanExpiresAt: json['nextPlanExpiresAt']?.toString(),
    );
  }
}

int _toInt(dynamic value) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  return int.tryParse(value.toString()) ?? 0;
}

double _toDouble(dynamic value) {
  if (value is double) {
    return value;
  }

  if (value is num) {
    return value.toDouble();
  }

  return double.tryParse(value.toString()) ?? 0;
}

List<String> _toStringList(dynamic value) {
  if (value is! List) {
    return const [];
  }

  return value.map((item) => item.toString()).toList(growable: false);
}

// ── Trainer public profile ────────────────────────────────────────────────────

class TrainerPublicProfile {
  const TrainerPublicProfile({
    required this.trainerId,
    required this.displayName,
    this.bio,
    this.avatarUrl,
  });

  final String trainerId;
  final String displayName;
  final String? bio;
  final String? avatarUrl;

  factory TrainerPublicProfile.fromJson(Map<String, dynamic> json) {
    return TrainerPublicProfile(
      trainerId: (json['trainerId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      bio: json['bio']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
    );
  }
}
