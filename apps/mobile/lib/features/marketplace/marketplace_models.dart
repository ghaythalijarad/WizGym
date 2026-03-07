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

  factory GymSummary.fromJson(Map<String, dynamic> json) {
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

  factory GymDetail.fromJson(Map<String, dynamic> json) {
    final facilitiesRaw = json['facilities'];
    final productsRaw = json['products'];
    final plansRaw = json['subscriptionPlans'];

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
  });

  final String userId;
  final String userName;
  final String gymId;
  final String status; // PENDING | ACTIVE | REJECTED
  final String joinedAt;
  final String? selectedPlanId;

  bool get isPending => status == 'PENDING';
  bool get isActive => status == 'ACTIVE';

  factory GymMemberItem.fromJson(Map<String, dynamic> json) {
    return GymMemberItem(
      userId: (json['userId'] ?? '').toString(),
      userName: (json['userName'] ?? '').toString(),
      gymId: (json['gymId'] ?? '').toString(),
      status: (json['status'] ?? 'PENDING').toString(),
      joinedAt: (json['joinedAt'] ?? '').toString(),
      selectedPlanId: json['selectedPlanId']?.toString(),
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
