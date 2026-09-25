import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Fetches a receipt schema's `image` section URL (typically a tenant's
/// logo) as raw bytes, for both the ESC/POS and PDF renderers to decode
/// themselves. Deliberately its own plain [Dio] instance, not the app's API
/// client — an `image` section's `value` is an arbitrary external URL (a
/// CDN), not this app's own API, so none of the API client's base URL/auth
/// interceptors apply.
class ReceiptImageLoader {
  ReceiptImageLoader._();

  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
    ),
  );

  /// Returns `null` on any failure (bad URL, network error, timeout,
  /// non-2xx) — a broken/unreachable logo must never stop the rest of the
  /// receipt from rendering or printing.
  static Future<Uint8List?> fetchBytes(String url) async {
    if (url.isEmpty) return null;
    try {
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = response.data;
      if (data == null || data.isEmpty) return null;
      return Uint8List.fromList(data);
    } catch (_) {
      return null;
    }
  }
}
