import 'package:flutter/services.dart';

/// Receives the route/entityId/type a push notification was tapped with, from
/// the native side (see android/app/.../MainActivity.kt`handleNotificationIntent`).
///
/// Two delivery paths, mirroring the standard deep-link pattern (same shape as
/// e.g. `uni_links`'s `getInitialLink` + `linkStream`):
///  * [consumeInitialRoute] — a pull, for a cold start launched by tapping a
///    notification. Native caches the tapped intent's extras because the Dart
///    side isn't listening yet when that intent is delivered; this reads them
///    once and native clears its copy.
///  * [onTap] — a push, for a tap while the app is already running (warm/
///    foreground), where the native side calls straight into the listener.
class NotificationRouter {
  NotificationRouter._();

  static const _channel = MethodChannel('com.retailx.store_manager/notifications');
  static bool _listening = false;

  /// Called with `{route, entityId, type}` when a notification is tapped
  /// while the app is already running.
  static void Function(Map<String, String> data)? onTap;

  /// Idempotent — safe to call every time the root widget rebuilds.
  static void startListening() {
    if (_listening) return;
    _listening = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onNotificationTap') return;
      final data = _asStringMap(call.arguments);
      if (data != null) onTap?.call(data);
    });
  }

  /// Null if the app wasn't launched by tapping a notification, or the value
  /// has already been consumed once.
  static Future<Map<String, String>?> consumeInitialRoute() async {
    try {
      final result = await _channel.invokeMethod('getInitialNotificationRoute');
      return _asStringMap(result);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static Map<String, String>? _asStringMap(Object? raw) {
    if (raw is! Map) return null;
    final route = raw['route']?.toString();
    if (route == null || route.isEmpty) return null;
    return raw.map((key, value) => MapEntry(key.toString(), value?.toString() ?? ''));
  }
}
