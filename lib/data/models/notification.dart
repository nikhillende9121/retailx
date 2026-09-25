import '../../core/json.dart';

/// Named `AppNotification`, not `Notification` — that name is already taken by
/// Flutter's own `NotificationListener` machinery (`package:flutter/widgets.dart`).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    this.data,
    required this.isRead,
    this.readAt,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String message;
  final String type;

  /// Carries the same `route`/`entityId` pair as the push payload — see
  /// [route] / [entityId] and `notification_targets.dart`.
  final Map<String, dynamic>? data;
  final bool isRead;
  final String? readAt;
  final String createdAt;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: asString(json['id']) ?? '',
      title: asString(json['title']) ?? '',
      message: asString(json['message']) ?? '',
      type: asString(json['type']) ?? 'GENERAL',
      data: asMap(json['data']),
      isRead: asBool(json['isRead']),
      readAt: asString(json['readAt']),
      createdAt: asString(json['createdAt']) ?? '',
    );
  }

  String? get route => asString(data?['route']);
  String? get entityId => asString(data?['entityId']);

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        title: title,
        message: message,
        type: type,
        data: data,
        isRead: isRead ?? this.isRead,
        readAt: readAt,
        createdAt: createdAt,
      );
}
