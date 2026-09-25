import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/constants.dart';
import 'demo_backend.dart';

/// Holds the JWT pair and the server address.
///
/// Tokens live in platform-backed secure storage (Android Keystore /
/// iOS Keychain) — never plain prefs. Values are also mirrored in memory so the
/// Dio interceptor can attach a header without an async read per request.
class TokenStore {
  TokenStore({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _kAccess = 'access_token';
  static const _kRefresh = 'refresh_token';
  static const _kBaseUrl = 'base_url';

  /// Marks a server address the user typed themselves.
  ///
  /// Without this, a saved copy of yesterday's default silently outranks a new
  /// one shipped in an update — the app would keep calling the old dev machine
  /// and look broken. A stored URL is only honoured when it was a deliberate
  /// override; otherwise the current default wins. Storage written before this
  /// key existed has no flag, so it's treated as non-custom and upgrades.
  static const _kBaseUrlCustom = 'base_url_is_custom';
  static const _kTenant = 'last_tenant_code';
  static const _kEmail = 'last_email';
  static const _kDeviceId = 'device_id';

  /// 'system' | 'light' | 'dark'. Not a secret, but this is already the one place
  /// the app persists anything, and adding a second storage plugin for one string
  /// buys nothing.
  static const _kThemeMode = 'theme_mode';

  /// The last Bluetooth receipt printer paired from the picker sheet — same
  /// reasoning as [_kThemeMode]: one more string doesn't earn a second
  /// storage plugin.
  static const _kPrinterAddress = 'printer_address';
  static const _kPrinterName = 'printer_name';

  final FlutterSecureStorage _storage;

  String? _accessToken;
  String? _refreshToken;
  String _baseUrl = kDefaultApiBaseUrl;
  String? _lastTenantCode;
  String? _lastEmail;
  String? _deviceId;
  String _themeMode = 'system';
  String? _printerAddress;
  String? _printerName;
  bool _loaded = false;

  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String get baseUrl => _baseUrl;
  String? get lastTenantCode => _lastTenantCode;
  String? get lastEmail => _lastEmail;
  String? get deviceId => _deviceId;

  /// 'system' | 'light' | 'dark'.
  String get themeMode => _themeMode;

  /// Bluetooth MAC address of the last paired receipt printer, or null if
  /// none has been chosen yet.
  String? get printerAddress => _printerAddress;
  String? get printerName => _printerName;
  bool get hasSession => (_accessToken ?? '').isNotEmpty;

  Future<void> load() async {
    if (_loaded) return;
    try {
      final all = await _storage.readAll();
      _accessToken = all[_kAccess];
      _refreshToken = all[_kRefresh];
      final saved = all[_kBaseUrl];
      final isCustom = all[_kBaseUrlCustom] == 'true';
      if (isCustom && saved != null && saved.isNotEmpty) {
        _baseUrl = saved;
      } else {
        _baseUrl = kDefaultApiBaseUrl;
      }
      _publishOrigin(_baseUrl);
      _lastTenantCode = all[_kTenant];
      _lastEmail = all[_kEmail];
      _deviceId = all[_kDeviceId];
      if (_deviceId == null || _deviceId!.isEmpty) {
        _deviceId = _generateDeviceId();
        await _storage.write(key: _kDeviceId, value: _deviceId);
      }
      final mode = all[_kThemeMode];
      if (mode == 'light' || mode == 'dark' || mode == 'system') {
        _themeMode = mode!;
      }
      _printerAddress = all[_kPrinterAddress];
      _printerName = all[_kPrinterName];
    } catch (_) {
      // A corrupt keystore entry (can happen after a restore to a new device)
      // must not brick the app — fall back to a signed-out state.
      _accessToken = null;
      _refreshToken = null;
    }
    _loaded = true;
  }

  String _generateDeviceId() {
    final random = Random();
    final parts = List.generate(4, (_) => random.nextInt(0x10000).toRadixString(16).padLeft(4, '0'));
    final timestamp = DateTime.now().millisecondsSinceEpoch.toRadixString(16);
    return 'dev-$timestamp-${parts.join('-')}';
  }

  Future<void> setDeviceId(String id) async {
    _deviceId = id;
    await _storage.write(key: _kDeviceId, value: id);
  }

  Future<void> saveTokens(String access, String refresh) async {
    _accessToken = access;
    _refreshToken = refresh;
    // Demo tokens are memory-only. Persisting them means the next cold start
    // finds a "session", sends `demo-access-token` to the real server, and
    // reports an expired session — two junk requests and a misleading message.
    if (DemoBackend.enabled) return;
    await _storage.write(key: _kAccess, value: access);
    await _storage.write(key: _kRefresh, value: refresh);
  }

  Future<void> setBaseUrl(String url) async {
    _baseUrl = normalizeBaseUrl(url);
    _publishOrigin(_baseUrl);
    await _storage.write(key: _kBaseUrl, value: _baseUrl);
    // Only a value that differs from the shipped default counts as an override.
    await _storage.write(
      key: _kBaseUrlCustom,
      value: _baseUrl == kDefaultApiBaseUrl ? 'false' : 'true',
    );
  }

  /// Survives sign-out on purpose: how the screen looks is a property of the
  /// device and the shop's lighting, not of whoever is logged in.
  Future<void> setThemeMode(String mode) async {
    _themeMode = mode;
    await _storage.write(key: _kThemeMode, value: mode);
  }

  /// Remembers the paired receipt printer — same "survives sign-out"
  /// reasoning as [setThemeMode]: the printer is wired to this device/
  /// counter, not to whoever is signed in.
  Future<void> setPrinter(String address, String name) async {
    _printerAddress = address;
    _printerName = name;
    await _storage.write(key: _kPrinterAddress, value: address);
    await _storage.write(key: _kPrinterName, value: name);
  }

  Future<void> clearPrinter() async {
    _printerAddress = null;
    _printerName = null;
    await _storage.delete(key: _kPrinterAddress);
    await _storage.delete(key: _kPrinterName);
  }

  Future<void> rememberLogin(String tenantCode, String email) async {
    _lastTenantCode = tenantCode;
    _lastEmail = email;
    // Don't leave 'demo' prefilled in the tenant field on the next launch.
    if (DemoBackend.enabled) return;
    await _storage.write(key: _kTenant, value: tenantCode);
    await _storage.write(key: _kEmail, value: email);
  }

  /// There is no server-side logout — dropping the tokens *is* logging out.
  Future<void> clear() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: _kAccess);
    await _storage.delete(key: _kRefresh);
  }
}

/// Origin of the configured API — e.g. `http://192.168.1.7:3000`.
///
/// The API returns product images as a bare `images` array, and those entries
/// may be server-relative paths (`/uploads/rice.jpg`). Widgets need an absolute
/// URL, and they have no business reaching into the session to build one, so the
/// origin is published here whenever the base URL changes.
String? gServerOrigin;

void _publishOrigin(String baseUrl) {
  final uri = Uri.tryParse(baseUrl);
  if (uri != null && uri.host.isNotEmpty) gServerOrigin = uri.origin;
}

/// Absolute URL for an image path the API gave us, or null when there's nothing
/// usable. Already-absolute URLs pass through untouched.
String? absoluteUrl(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final value = raw.trim();
  if (value.startsWith('http://') || value.startsWith('https://')) return value;
  final origin = gServerOrigin;
  if (origin == null) return null;
  return value.startsWith('/') ? '$origin$value' : '$origin/$value';
}

/// Guarantees a single trailing slash so relative paths concatenate cleanly.
String normalizeBaseUrl(String raw) {
  var url = raw.trim();
  if (url.isEmpty) return kDefaultApiBaseUrl;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    url = 'http://$url';
  }
  while (url.endsWith('/')) {
    url = url.substring(0, url.length - 1);
  }
  return '$url/';
}
