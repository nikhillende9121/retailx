import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../core/errors.dart';
import '../core/json.dart';
import 'demo_backend.dart';
import 'request_log.dart';
import 'token_store.dart' show TokenStore, normalizeBaseUrl;

/// Fires one real HTTP request at [baseUrl] and reports exactly what came back.
///
/// Deliberately bypasses [ApiClient] — no demo backend, no tokens, no retry — so
/// it answers one question only: can this device reach that server? An
/// unauthenticated `GET /auth/me` is the probe, so a `401 UNAUTHENTICATED` is a
/// *success*: the server is there and talking.
Future<String> probeServer(String baseUrl) async {
  final normalized = normalizeBaseUrl(baseUrl);
  final url = '${normalized}auth/me';
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      validateStatus: (_) => true,
    ),
  );

  final watch = Stopwatch()..start();
  try {
    final response = await dio.get<dynamic>(url);
    final ms = watch.elapsedMilliseconds;
    final body = response.data?.toString() ?? '';
    final preview = body.length > 300 ? '${body.substring(0, 300)}…' : body;
    final verdict = response.statusCode == 401
        ? 'Reachable. A 401 here is expected — no token was sent.'
        : response.statusCode == 404
            ? 'Reached a server, but /auth/me is not there. Check that the URL '
                'ends at /api/v1.'
            : 'Reachable.';
    debugPrint('[PROBE] ${response.statusCode} $url (${ms}ms)');
    return 'GET $url\n\nHTTP ${response.statusCode} in ${ms}ms\n$verdict\n\n$preview';
  } on DioException catch (e) {
    debugPrint('[PROBE] ${e.type.name} $url — ${e.message}');
    final hint = switch (e.type) {
      DioExceptionType.connectionTimeout =>
        'Nothing answered. Usually: the phone is on a different network from '
            'this machine, or a firewall is blocking port 3000.',
      DioExceptionType.connectionError =>
        'Connection refused or host unreachable. Usually: the server is bound '
            'to localhost only — start it on 0.0.0.0 — or the IP has changed.',
      DioExceptionType.receiveTimeout =>
        'Connected, but the server never finished responding.',
      DioExceptionType.badCertificate =>
        'TLS certificate rejected. For local dev use http, not https.',
      _ => 'Request failed before a response arrived.',
    };
    return 'GET $url\n\nFailed: ${e.type.name}\n$hint\n\n${e.message ?? ''}';
  }
}

/// Thin transport over the REST API.
///
/// Responsibilities, all of which every screen would otherwise repeat:
///  * points at whatever base URL is currently configured (editable at runtime)
///  * attaches `Authorization: Bearer <accessToken>`
///  * unwraps the `{ success, data, message }` / `{ success, error }` envelope
///  * turns every failure into an [AppError]
///  * on a 401 `UNAUTHENTICATED`, refreshes once and replays the request; if the
///    refresh itself fails, clears tokens and signals a forced re-login
///    (MOBILE_API_GUIDE.md §2)
class ApiClient {
  ApiClient(this._tokens, {this.onSessionExpired}) {
    _dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 25),
        // Non-2xx bodies carry the error envelope, so read them rather than
        // letting Dio throw before we can see `error.code`.
        validateStatus: (_) => true,
        contentType: Headers.jsonContentType,
        responseType: ResponseType.json,
      ),
    );
    _plain = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (_) => true,
        contentType: Headers.jsonContentType,
      ),
    );
  }

  final TokenStore _tokens;

  /// Called when the refresh token is dead and the user has to sign in again.
  final void Function()? onSessionExpired;

  late final Dio _dio;
  late final Dio _plain;

  /// In-flight refresh, so ten parallel 401s trigger one refresh, not ten.
  Future<bool>? _refreshInFlight;

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send('POST', path, body: body, query: query);

  Future<dynamic> patch(String path, {Object? body}) =>
      _send('PATCH', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, dynamic>? query,
    Object? body,
  }) async {
    final watch = Stopwatch()..start();

    // Recorded for the in-app request log — the only way to see Flutter's
    // traffic on-device, since Android Studio's Network Inspector can't.
    final entry = RequestLog.instance.record(RequestRecord(
      method: method,
      path: path,
      query: _queryTail(query),
      requestBody: preview(body),
      startedAt: DateTime.now(),
    ));

    // Demo mode: answer from memory instead of the network. Off unless the
    // login screen's demo button switched it on.
    if (DemoBackend.enabled) {
      entry?.fromDemo = true;
      _log('DEMO', '→ $method /$path${_queryTail(query)}');
      try {
        final result = await DemoBackend.instance.handle(method, path, query, body);
        _log('DEMO', '← ok   $method /$path (${watch.elapsedMilliseconds}ms)');
        entry
          ?..status = 200
          ..elapsedMs = watch.elapsedMilliseconds
          ..responsePreview = preview(result);
        RequestLog.instance.complete(entry);
        return result;
      } on AppError catch (error) {
        _log('DEMO', '← ${error.code} $method /$path');
        entry
          ?..errorCode = error.code
          ..errorMessage = error.message
          ..elapsedMs = watch.elapsedMilliseconds;
        RequestLog.instance.complete(entry);
        rethrow;
      }
    }

    _log('API', '→ $method ${_tokens.baseUrl}$path${_queryTail(query)}');

    final isAuthExchange = path == 'auth/login' || path == 'auth/refresh';

    Response<dynamic> response;
    try {
      response = await _raw(method, path, query, body);
    } on AppError catch (error) {
      _log('API', '← ${error.code} $method /$path '
          '(${watch.elapsedMilliseconds}ms) ${error.message}');
      entry
        ?..errorCode = error.code
        ..errorMessage = error.message
        ..elapsedMs = watch.elapsedMilliseconds;
      RequestLog.instance.complete(entry);
      rethrow;
    }
    final status = response.statusCode ?? 0;
    _log('API', '← $status $method /$path (${watch.elapsedMilliseconds}ms)');
    // On a failure the body is where the reason lives — a 500's stack trace, a
    // 400's field errors. Printing it saves a round trip to the server logs.
    if (status >= 400) {
      _log('API', '   body: ${preview(response.data, limit: 900)}');
    }
    entry
      ?..status = response.statusCode
      ..elapsedMs = watch.elapsedMilliseconds
      ..responsePreview = preview(response.data, limit: 900);
    RequestLog.instance.complete(entry);

    if (response.statusCode == 401 && !isAuthExchange) {
      final refreshed = await _refresh();
      if (!refreshed) {
        await _tokens.clear();
        onSessionExpired?.call();
        throw const AppError(
          code: ErrorCodes.unauthenticated,
          message: 'Session expired. Please sign in again.',
          status: 401,
        );
      }
      _log('API', '↻ refreshed, replaying $method /$path');
      response = await _raw(method, path, query, body);
      _log('API', '← ${response.statusCode} $method /$path (replay)');

      // Still 401 with a token we just minted: the account itself is gone or
      // suspended. Don't loop — end the session once, here.
      if (response.statusCode == 401) {
        await _tokens.clear();
        onSessionExpired?.call();
        throw const AppError(
          code: ErrorCodes.unauthenticated,
          message: 'Session expired. Please sign in again.',
          status: 401,
        );
      }
    }

    return _unwrap(response);
  }

  Future<Response<dynamic>> _raw(
    String method,
    String path,
    Map<String, dynamic>? query,
    Object? body,
  ) async {
    // Re-read every time: the user can change the server on the login screen.
    _dio.options.baseUrl = _tokens.baseUrl;
    final headers = <String, dynamic>{};
    final token = _tokens.accessToken;
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    try {
      return await _dio.request<dynamic>(
        path,
        data: body,
        queryParameters: _clean(query),
        options: Options(method: method, headers: headers),
      );
    } on DioException catch (e) {
      throw _fromDio(e);
    }
  }

  /// Uses a bare Dio: the refresh call must not itself be intercepted or
  /// carry the (expired) access token.
  Future<bool> _refresh() {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final future = _doRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  Future<bool> _doRefresh() async {
    final refreshToken = _tokens.refreshToken;
    if (refreshToken == null || refreshToken.isEmpty) return false;
    _plain.options.baseUrl = _tokens.baseUrl;
    try {
      final response = await _plain.post<dynamic>(
        'auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final body = asMap(response.data);
      if (response.statusCode != 200 || body == null || body['success'] != true) {
        return false;
      }
      final data = asMap(body['data']);
      final access = asString(data?['accessToken']);
      final newRefresh = asString(data?['refreshToken']) ?? refreshToken;
      if (access == null) return false;
      await _tokens.saveTokens(access, newRefresh);
      return true;
    } on DioException catch (e) {
      // A network blip is not a dead session. Throwing here surfaces a
      // retryable network error and leaves the tokens in place, rather than
      // signing the cashier out mid-shift because the wifi dropped.
      throw _fromDio(e);
    } catch (_) {
      return false;
    }
  }

  dynamic _unwrap(Response<dynamic> response) {
    final status = response.statusCode ?? 0;
    final body = asMap(response.data);

    if (body != null && body.containsKey('success')) {
      if (body['success'] == true) return body['data'];
      final error = asMap(body['error']);
      throw AppError(
        code: asString(error?['code']) ?? codeForStatus(status),
        message: asString(error?['message']) ??
            asString(body['message']) ??
            'Request failed',
        status: status,
        // Mutually exclusive by shape: a list of Zod issues unpacks into
        // fieldErrors, a flat object (e.g. CREDIT_LIMIT_EXCEEDED's
        // currentBalance/creditLimit/attemptedChargeAmount) into details —
        // asMap/asMapList each return empty for the other's shape.
        fieldErrors: parseFieldErrors(error?['details']),
        details: asMap(error?['details']) ?? const {},
      );
    }

    // Tolerate a handler that returns a bare payload.
    if (status >= 200 && status < 300) return response.data;

    throw AppError(
      code: codeForStatus(status),
      message: asString(body?['message']) ?? 'Request failed ($status)',
      status: status,
    );
  }

  AppError _fromDio(DioException e) {
    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return AppError.network('The server took too long to respond.');
      case DioExceptionType.badCertificate:
        return AppError.network("The server's security certificate isn't valid.");
      case DioExceptionType.connectionError:
        return AppError.network(
          'Could not reach ${_tokens.baseUrl}. Check the server address and the network.',
        );
      case DioExceptionType.cancel:
        return AppError.network('Request cancelled.');
      case DioExceptionType.badResponse:
        final response = e.response;
        if (response != null) return _asError(response);
        return AppError.network();
      default:
        // Covers DioExceptionType.unknown and any member a future dio adds
        // (5.11 introduced transformTimeout) — all are "the request didn't
        // complete", which is what AppError.network already says.
        return AppError.network();
    }
  }

  AppError _asError(Response<dynamic> response) {
    try {
      _unwrap(response);
    } on AppError catch (err) {
      return err;
    } catch (_) {
      // fall through
    }
    return AppError(
      code: codeForStatus(response.statusCode),
      message: 'Request failed (${response.statusCode}).',
      status: response.statusCode,
    );
  }

  /// One line per request, debug builds only.
  ///
  /// Tagged so `flutter run` output (or `adb logcat`) can be filtered: `[API]`
  /// for real network traffic, `[DEMO]` for calls the in-memory backend
  /// answered. If you see `[DEMO]` lines, nothing is reaching your server —
  /// that's demo mode, not a connection problem.
  void _log(String tag, String message) {
    if (kDebugMode) debugPrint('[$tag] $message');
  }

  String _queryTail(Map<String, dynamic>? query) {
    final cleaned = _clean(query);
    if (cleaned == null) return '';
    final pairs =
        cleaned.entries.map((e) => '${e.key}=${e.value}').join('&');
    return '?$pairs';
  }

  Map<String, dynamic>? _clean(Map<String, dynamic>? query) {
    if (query == null) return null;
    final out = <String, dynamic>{};
    query.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      out[key] = value;
    });
    return out.isEmpty ? null : out;
  }
}
