import 'json.dart';

/// Error codes the API can return, per MOBILE_API_GUIDE.md §6.
class ErrorCodes {
  ErrorCodes._();

  static const validation = 'VALIDATION_ERROR';
  static const unauthenticated = 'UNAUTHENTICATED';
  static const invalidCredentials = 'INVALID_CREDENTIALS';
  static const featureNotEnabled = 'FEATURE_NOT_ENABLED';
  static const permissionDenied = 'PERMISSION_DENIED';
  static const subscriptionExpired = 'SUBSCRIPTION_EXPIRED';
  static const notFound = 'RESOURCE_NOT_FOUND';
  static const conflict = 'CONFLICT';
  static const insufficientStock = 'INSUFFICIENT_STOCK';
  static const creditLimitExceeded = 'CREDIT_LIMIT_EXCEEDED';
  static const internal = 'INTERNAL_ERROR';

  /// Client-side only.
  static const network = 'NETWORK_ERROR';
  static const unknown = 'UNKNOWN_ERROR';
}

/// A single failed request, already translated out of the response envelope.
class AppError implements Exception {
  const AppError({
    required this.code,
    required this.message,
    this.status,
    this.fieldErrors = const {},
    this.details = const {},
  });

  final String code;
  final String message;
  final int? status;

  /// Field path -> message, unpacked from `error.details` on a 400 —
  /// `details` there is a list of Zod issues (`{path, message}`).
  final Map<String, String> fieldErrors;

  /// The raw `error.details` object for codes where it's a flat data payload
  /// rather than a list of field issues — e.g. `CREDIT_LIMIT_EXCEEDED`'s
  /// `{currentBalance, creditLimit, attemptedChargeAmount}`. Empty for any
  /// error whose `details` came back as a list (or wasn't sent at all) —
  /// see [fieldErrors] for that shape instead.
  final Map<String, dynamic> details;

  bool get isCreditLimitExceeded => code == ErrorCodes.creditLimitExceeded;

  factory AppError.network([String? message]) => AppError(
        code: ErrorCodes.network,
        message: message ?? 'Could not reach the server.',
      );

  bool get isUnauthenticated => code == ErrorCodes.unauthenticated;
  bool get isValidation => code == ErrorCodes.validation;

  /// Whether retrying the exact same request could plausibly succeed.
  bool get isRetryable =>
      code == ErrorCodes.network || code == ErrorCodes.internal;

  /// Copy for a code, per the UI-treatment table in ANDROID_APP_PROMPT.md.
  String get uiMessage {
    switch (code) {
      case ErrorCodes.validation:
        // Field errors are shown inline; this is the fallback banner text.
        return message.isNotEmpty ? message : 'Please check the details below.';
      case ErrorCodes.invalidCredentials:
        return 'Wrong tenant code, email or password.';
      case ErrorCodes.unauthenticated:
        return 'Your session expired. Please sign in again.';
      case ErrorCodes.featureNotEnabled:
        return 'Not available on your plan.';
      case ErrorCodes.permissionDenied:
        return "You're not allowed to do that.";
      case ErrorCodes.subscriptionExpired:
        return 'This subscription has expired. Contact your administrator.';
      case ErrorCodes.notFound:
        return 'Not found.';
      case ErrorCodes.insufficientStock:
        // The one actionable error in the table.
        return message.isNotEmpty ? message : 'Not enough stock.';
      case ErrorCodes.conflict:
        return message.isNotEmpty ? message : 'That conflicts with existing data.';
      case ErrorCodes.network:
        // Keep the specific diagnosis (timeout, bad certificate, which host was
        // unreachable) — with an editable server URL that detail is the fix.
        return message.isNotEmpty
            ? message
            : 'Could not reach the server. Check the connection and try again.';
      case ErrorCodes.internal:
        return 'Something went wrong on the server. Try again.';
      default:
        if (code.startsWith('DUPLICATE_')) {
          return message.isNotEmpty ? message : 'That value is already in use.';
        }
        return message.isNotEmpty ? message : 'Something went wrong.';
    }
  }

  @override
  String toString() => 'AppError($code, $status): $message';
}

/// Unpacks `error.details` — Zod issues arrive as a list of
/// `{ path: [...], message }` (or `{ field, message }`) objects.
Map<String, String> parseFieldErrors(dynamic details) {
  final out = <String, String>{};
  for (final item in asMapList(details)) {
    final rawPath = item['path'] ?? item['field'] ?? item['name'];
    String key;
    if (rawPath is List) {
      key = rawPath.map((e) => e.toString()).join('.');
    } else {
      key = asString(rawPath) ?? '';
    }
    final message = firstString(item, ['message', 'msg']) ?? 'Invalid value';
    if (key.isEmpty) {
      out['_'] = message;
    } else {
      out[key] = message;
    }
  }
  return out;
}

/// Best-effort code for a status when the body carried no `error.code`.
String codeForStatus(int? status) {
  switch (status) {
    case 400:
      return ErrorCodes.validation;
    case 401:
      return ErrorCodes.unauthenticated;
    case 403:
      return ErrorCodes.permissionDenied;
    case 404:
      return ErrorCodes.notFound;
    case 409:
      return ErrorCodes.conflict;
    case 422:
      return ErrorCodes.insufficientStock;
    case 500:
    case 502:
    case 503:
      return ErrorCodes.internal;
    default:
      return ErrorCodes.unknown;
  }
}
