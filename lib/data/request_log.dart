import 'package:flutter/foundation.dart';

/// One recorded call.
class RequestRecord {
  RequestRecord({
    required this.method,
    required this.path,
    required this.startedAt,
    this.query,
    this.requestBody,
  });

  final String method;
  final String path;
  final DateTime startedAt;
  final String? query;
  final String? requestBody;

  int? status;
  String? errorCode;
  String? errorMessage;
  String? responsePreview;
  int elapsedMs = 0;
  bool fromDemo = false;

  bool get pending => status == null && errorCode == null;

  bool get ok => status != null && status! >= 200 && status! < 300;

  String get label => '$method /$path${query ?? ''}';

  /// `200`, `422`, or the error code when the request never got a response.
  String get outcome {
    if (pending) return '…';
    if (status != null) return '$status';
    return errorCode ?? '?';
  }
}

/// In-memory ring buffer of recent API calls, so the app can show its own
/// network activity on-device.
///
/// This exists because Android Studio's Network Inspector cannot see Flutter
/// traffic — it only instruments the Java/Kotlin HTTP stacks, while Dart talks
/// to sockets directly. Rather than make debugging depend on a laptop with
/// DevTools attached, the app keeps its own log.
///
/// Debug builds only: [record] is a no-op in release, so nothing is retained in
/// a shipped app.
class RequestLog {
  RequestLog._();

  static final RequestLog instance = RequestLog._();

  static const int maxEntries = 120;

  /// Rebuilds the log screen as calls come and go.
  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  final List<RequestRecord> _records = [];

  List<RequestRecord> get records => List.unmodifiable(_records);

  int get failureCount =>
      _records.where((r) => !r.pending && !r.ok).length;

  RequestRecord? record(RequestRecord entry) {
    if (!kDebugMode) return null;
    _records.insert(0, entry);
    if (_records.length > maxEntries) _records.removeLast();
    revision.value++;
    return entry;
  }

  /// Call when a request settles, so the entry stops showing as in-flight.
  void complete(RequestRecord? entry) {
    if (entry == null) return;
    revision.value++;
  }

  void clear() {
    _records.clear();
    revision.value++;
  }
}

/// A framework error, captured with the part that actually identifies it.
class ErrorRecord {
  ErrorRecord({
    required this.summary,
    required this.at,
    this.library,
    this.widget,
    this.stack,
  });

  final String summary;
  final DateTime at;
  final String? library;

  /// Flutter's "relevant error-causing widget", when it names one — usually the
  /// single most useful line in the whole report.
  final String? widget;
  final String? stack;
}

/// Captures framework errors so they can be read on the device.
///
/// Layout assertions print ~90 lines to the console, and the part that matters
/// (the assertion and the error-causing widget) is at the *top* — the first
/// thing to scroll away. Keeping the head of each report in the app means it can
/// be read, and copied, without a terminal.
class ErrorLog {
  ErrorLog._();

  static final ErrorLog instance = ErrorLog._();

  static const int maxEntries = 30;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final List<ErrorRecord> _records = [];

  List<ErrorRecord> get records => List.unmodifiable(_records);

  /// Installs the handler. Debug builds only — release keeps Flutter's default.
  static void install() {
    if (!kDebugMode) return;
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      instance._add(details);
      // Still print it: the console remains the record of truth.
      previous?.call(details);
    };
  }

  void _add(FlutterErrorDetails details) {
    final exception = details.exception.toString();
    _records.insert(
      0,
      ErrorRecord(
        summary: exception.length > 400
            ? '${exception.substring(0, 400)}…'
            : exception,
        at: DateTime.now(),
        library: details.library,
        widget: details.context?.toDescription(),
        stack: preview(details.stack, limit: 700),
      ),
    );
    if (_records.length > maxEntries) _records.removeLast();
    revision.value++;
  }

  void clear() {
    _records.clear();
    revision.value++;
  }
}

/// Trims a body or response for display — enough to identify a payload without
/// holding whole responses in memory.
String? preview(Object? value, {int limit = 600}) {
  if (value == null) return null;
  final text = value.toString();
  if (text.isEmpty) return null;
  return text.length > limit ? '${text.substring(0, limit)}…' : text;
}
