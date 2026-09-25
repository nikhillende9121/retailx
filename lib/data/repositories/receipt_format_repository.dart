import '../../core/errors.dart';
import '../../core/json.dart';
import '../api_client.dart';
import '../models/receipt_format.dart';

/// Fetches the receipt format for a POS device from the backend.
///
/// See `pos_receipt_format_guide.md` §2.1 and §2.2 for the wire contract.
/// Resolution precedence on the server: POS device → store → tenant → global
/// default. Returns null on 404 (no format resolved at any level).
class ReceiptFormatRepository {
  ReceiptFormatRepository(this._api);

  final ApiClient _api;

  /// In-memory cache — holds the last successfully fetched format so the
  /// receipt screen doesn't wait on a network call every time it opens.
  ReceiptFormat? _cached;

  /// The version of the cached format, for lightweight staleness checks.
  int? _cachedVersion;

  /// The last format this repo successfully fetched (or null).
  ReceiptFormat? get cached => _cached;

  /// Fetches the full receipt format for [posId].
  ///
  /// Returns null on 404 (no format assigned anywhere in the resolution
  /// chain) — the caller should fall back to the bundled default.
  Future<ReceiptFormat?> getFormat(String posId) async {
    try {
      final data = await _api.get('pos/$posId/receipt-format');
      final map = asMap(data);
      if (map == null) return null;
      final format = ReceiptFormat.fromJson(map);
      _cached = format;
      _cachedVersion = format.version;
      return format;
    } on AppError catch (e) {
      // 404 means no format resolved — use the bundled default.
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Lightweight version check — call on startup to decide whether the full
  /// payload needs to be refetched.
  ///
  /// Returns the server's current version, or null if no format is assigned.
  Future<int?> getVersion(String posId) async {
    try {
      final data = await _api.get('pos/$posId/receipt-format/version');
      final map = asMap(data);
      if (map == null) return null;
      return asInt(map['version']);
    } on AppError catch (e) {
      if (e.status == 404) return null;
      rethrow;
    }
  }

  /// Fetches the format only if the server's version differs from what's
  /// cached. Returns the (possibly cached) format, or null.
  Future<ReceiptFormat?> fetchIfStale(String posId) async {
    try {
      final serverVersion = await getVersion(posId);
      if (serverVersion == null) {
        _cached = null;
        _cachedVersion = null;
        return null;
      }
      if (_cachedVersion == serverVersion && _cached != null) {
        return _cached;
      }
      return getFormat(posId);
    } on AppError {
      // Network error during version check — return whatever we have cached.
      return _cached;
    }
  }
}
