enum GymApprovalStatus { pending, approved, rejected }

extension GymApprovalStatusX on GymApprovalStatus {
  static GymApprovalStatus fromApi(String value) {
    switch (value.toUpperCase()) {
      case 'APPROVED':
        return GymApprovalStatus.approved;
      case 'REJECTED':
        return GymApprovalStatus.rejected;
      default:
        return GymApprovalStatus.pending;
    }
  }

  String get apiValue {
    switch (this) {
      case GymApprovalStatus.pending:
        return 'PENDING';
      case GymApprovalStatus.approved:
        return 'APPROVED';
      case GymApprovalStatus.rejected:
        return 'REJECTED';
    }
  }
}

enum SubscriptionStatus { active, paused, canceled }

extension SubscriptionStatusX on SubscriptionStatus {
  static SubscriptionStatus fromApi(String value) {
    switch (value.toUpperCase()) {
      case 'PAUSED':
        return SubscriptionStatus.paused;
      case 'CANCELED':
        return SubscriptionStatus.canceled;
      default:
        return SubscriptionStatus.active;
    }
  }

  String get apiValue {
    switch (this) {
      case SubscriptionStatus.active:
        return 'ACTIVE';
      case SubscriptionStatus.paused:
        return 'PAUSED';
      case SubscriptionStatus.canceled:
        return 'CANCELED';
    }
  }
}

class AdminDashboardSummary {
  const AdminDashboardSummary({
    required this.pendingGymApprovals,
    required this.approvedGyms,
    required this.activeSubscriptions,
    required this.pausedSubscriptions,
  });

  final int pendingGymApprovals;
  final int approvedGyms;
  final int activeSubscriptions;
  final int pausedSubscriptions;

  factory AdminDashboardSummary.fromJson(Map<String, dynamic> json) {
    return AdminDashboardSummary(
      pendingGymApprovals: _toInt(json['pendingGymApprovals']),
      approvedGyms: _toInt(json['approvedGyms']),
      activeSubscriptions: _toInt(json['activeSubscriptions']),
      pausedSubscriptions: _toInt(json['pausedSubscriptions']),
    );
  }
}

class GymRequest {
  GymRequest({
    required this.id,
    required this.gymName,
    required this.ownerName,
    required this.city,
    required this.requestedDate,
    this.reviewNote,
    this.status = GymApprovalStatus.pending,
  });

  final String id;
  final String gymName;
  final String ownerName;
  final String city;
  final String requestedDate;
  final String? reviewNote;
  final GymApprovalStatus status;

  factory GymRequest.fromJson(Map<String, dynamic> json) {
    return GymRequest(
      id: (json['id'] ?? '').toString(),
      gymName: (json['gymName'] ?? '').toString(),
      ownerName: (json['ownerName'] ?? '').toString(),
      city: (json['city'] ?? '').toString(),
      requestedDate: _dateOnly(json['requestedAt']),
      reviewNote: json['reviewNote']?.toString(),
      status: GymApprovalStatusX.fromApi((json['status'] ?? 'PENDING').toString()),
    );
  }

  GymRequest copyWith({
    String? id,
    String? gymName,
    String? ownerName,
    String? city,
    String? requestedDate,
    String? reviewNote,
    GymApprovalStatus? status,
  }) {
    return GymRequest(
      id: id ?? this.id,
      gymName: gymName ?? this.gymName,
      ownerName: ownerName ?? this.ownerName,
      city: city ?? this.city,
      requestedDate: requestedDate ?? this.requestedDate,
      reviewNote: reviewNote ?? this.reviewNote,
      status: status ?? this.status,
    );
  }
}

class GymSubscription {
  GymSubscription({
    required this.id,
    required this.gymId,
    required this.gymName,
    required this.planName,
    required this.membersLimit,
    required this.nextBillingDate,
    required this.monthlyPrice,
    this.status = SubscriptionStatus.active,
  });

  final String id;
  final String gymId;
  final String gymName;
  final String planName;
  final int membersLimit;
  final String nextBillingDate;
  final int monthlyPrice;
  final SubscriptionStatus status;

  factory GymSubscription.fromJson(Map<String, dynamic> json) {
    return GymSubscription(
      id: (json['id'] ?? '').toString(),
      gymId: (json['gymId'] ?? '').toString(),
      gymName: (json['gymName'] ?? '').toString(),
      planName: (json['planName'] ?? '').toString(),
      membersLimit: _toInt(json['membersLimit']),
      nextBillingDate: _dateOnly(json['nextBillingDate']),
      monthlyPrice: _toInt(json['monthlyPrice']),
      status: SubscriptionStatusX.fromApi((json['status'] ?? 'ACTIVE').toString()),
    );
  }

  GymSubscription copyWith({
    String? id,
    String? gymId,
    String? gymName,
    String? planName,
    int? membersLimit,
    String? nextBillingDate,
    int? monthlyPrice,
    SubscriptionStatus? status,
  }) {
    return GymSubscription(
      id: id ?? this.id,
      gymId: gymId ?? this.gymId,
      gymName: gymName ?? this.gymName,
      planName: planName ?? this.planName,
      membersLimit: membersLimit ?? this.membersLimit,
      nextBillingDate: nextBillingDate ?? this.nextBillingDate,
      monthlyPrice: monthlyPrice ?? this.monthlyPrice,
      status: status ?? this.status,
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

String _dateOnly(dynamic value) {
  final raw = value?.toString() ?? '';
  if (raw.length >= 10) {
    return raw.substring(0, 10);
  }

  return raw;
}
