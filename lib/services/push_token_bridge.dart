import 'package:flutter/services.dart';

/// Hands the signed-in session (server address, access token, device id)
/// down to the native Android side, which owns FCM registration end to end
/// (see android/app/.../data/DeviceTokenSync.kt) — the device token itself
/// never needs to cross into Dart. Best-effort throughout: push registration
/// must never block or fail sign-in/sign-out.
class PushTokenBridge {
  static const _channel = MethodChannel('com.retailx.store_manager/push');

  static Future<void> syncSession({
    required String baseUrl,
    required String accessToken,
    required String deviceId,
  }) async {
    try {
      await _channel.invokeMethod('syncSession', {
        'baseUrl': baseUrl,
        'accessToken': accessToken,
        'deviceId': deviceId,
      });
    } on MissingPluginException {
      // iOS / no native handler registered.
    } on PlatformException {
      // Ignored — see class doc.
    }
  }

  static Future<void> clearSession() async {
    try {
      await _channel.invokeMethod('clearSession');
    } on MissingPluginException {
      // iOS / no native handler registered.
    } on PlatformException {
      // Ignored — see class doc.
    }
  }
}
