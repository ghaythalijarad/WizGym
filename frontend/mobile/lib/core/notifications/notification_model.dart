import 'package:flutter/material.dart';

enum NotificationType {
  newMember, // trainee joined gym
  newTrainer, // trainer joined / registered
  trainingPlan, // trainer sent you a plan
  workoutReminder, // daily workout reminder
  adminBroadcast, // message from admin dashboard
  generic,
}

class AppNotification {
  const AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
    this.payload,
  });

  final String id;
  final NotificationType type;
  final String title;
  final String body;
  final DateTime createdAt;
  final bool isRead;
  final Map<String, dynamic>? payload;

  IconData get icon {
    switch (type) {
      case NotificationType.newMember:
        return Icons.person_add_outlined;
      case NotificationType.newTrainer:
        return Icons.fitness_center_outlined;
      case NotificationType.trainingPlan:
        return Icons.assignment_outlined;
      case NotificationType.workoutReminder:
        return Icons.alarm_outlined;
      case NotificationType.adminBroadcast:
        return Icons.campaign_outlined;
      case NotificationType.generic:
        return Icons.notifications_outlined;
    }
  }

  Color get accentColor {
    switch (type) {
      case NotificationType.newMember:
        return const Color(0xFFC4B5FD);
      case NotificationType.newTrainer:
        return const Color(0xFFCAFC01);
      case NotificationType.trainingPlan:
        return const Color(0xFF67E8F9);
      case NotificationType.workoutReminder:
        return const Color(0xFFFBBF24);
      case NotificationType.adminBroadcast:
        return const Color(0xFFF0A8D0);
      case NotificationType.generic:
        return const Color(0xFFAAAAAA);
    }
  }

  String get relativeTime {
    final diff = DateTime.now().difference(createdAt);
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: isRead ?? this.isRead,
        payload: payload,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'createdAt': createdAt.toIso8601String(),
        'isRead': isRead,
        if (payload != null) 'payload': payload,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      type: NotificationType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => NotificationType.generic,
      ),
      title: json['title'] as String,
      body: json['body'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isRead: json['isRead'] as bool? ?? false,
      payload: json['payload'] as Map<String, dynamic>?,
    );
  }

  factory AppNotification.fromApiEvent(Map<String, dynamic> event) {
    final typeStr = (event['eventType'] ?? event['type'] ?? '').toString();
    final type = _typeFromApi(typeStr);
    return AppNotification(
      id: (event['id'] ?? DateTime.now().millisecondsSinceEpoch.toString())
          .toString(),
      type: type,
      title: _titleForType(type, event),
      body: (event['message'] ?? event['body'] ?? '').toString(),
      createdAt: event['createdAt'] != null
          ? DateTime.tryParse(event['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
      isRead: false,
      payload: event,
    );
  }

  static NotificationType _typeFromApi(String raw) {
    switch (raw.toUpperCase()) {
      case 'NEW_MEMBER':
      case 'MEMBER_JOINED':
        return NotificationType.newMember;
      case 'NEW_TRAINER':
      case 'TRAINER_JOINED':
      case 'TRAINER_REGISTERED':
        return NotificationType.newTrainer;
      case 'TRAINING_PLAN':
      case 'PLAN_SENT':
        return NotificationType.trainingPlan;
      case 'WORKOUT_REMINDER':
      case 'REMINDER':
        return NotificationType.workoutReminder;
      case 'ADMIN_BROADCAST':
      case 'BROADCAST':
        return NotificationType.adminBroadcast;
      default:
        return NotificationType.generic;
    }
  }

  static String _titleForType(
      NotificationType type, Map<String, dynamic> event) {
    final custom = event['title']?.toString();
    if (custom != null && custom.isNotEmpty) return custom;
    switch (type) {
      case NotificationType.newMember:
        return 'عضو جديد انضم للنادي';
      case NotificationType.newTrainer:
        return 'مدرب جديد انضم للنادي';
      case NotificationType.trainingPlan:
        return 'خطة تدريب جديدة';
      case NotificationType.workoutReminder:
        return 'تذكير التمرين اليومي';
      case NotificationType.adminBroadcast:
        return 'رسالة من الإدارة';
      case NotificationType.generic:
        return 'إشعار جديد';
    }
  }
}
