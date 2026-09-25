import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors.dart';
import '../core/json.dart';
import '../data/models/auth.dart';
import '../data/models/catalog.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/token_store.dart';
import '../services/push_token_bridge.dart';

sealed class SessionState {
  const SessionState();
}

/// Reading stored tokens / fetching `/auth/me`.
class SessionLoading extends SessionState {
  const SessionLoading();
}

class SessionLoggedOut extends SessionState {
  const SessionLoggedOut({this.notice});

  /// Shown once on the login screen, e.g. after a forced sign-out.
  final String? notice;
}

/// Signed in, but the account isn't pinned to a store and the tenant has more
/// than one — the user picks which store they're working from.
class SessionNeedsStore extends SessionState {
  const SessionNeedsStore(this.me, this.options);

  final Me me;
  final List<Warehouse> options;
}

class SessionReady extends SessionState {
  const SessionReady(this.me);

  final Me me;
}

class SessionController extends StateNotifier<SessionState> {
  SessionController({
    required AuthRepository auth,
    required CatalogRepository catalog,
    required TokenStore tokens,
  })  : _auth = auth,
        _catalog = catalog,
        _tokens = tokens,
        super(const SessionLoading());

  final AuthRepository _auth;
  final CatalogRepository _catalog;
  final TokenStore _tokens;

  Me? get me => switch (state) {
        SessionReady(me: final m) => m,
        SessionNeedsStore(me: final m) => m,
        _ => null,
      };

  String get baseUrl => _tokens.baseUrl;
  String? get lastTenantCode => _tokens.lastTenantCode;
  String? get lastEmail => _tokens.lastEmail;

  /// Restores a stored session on cold start.
  Future<void> bootstrap() async {
    await _tokens.load();
    if (!_tokens.hasSession) {
      state = const SessionLoggedOut();
      return;
    }
    state = const SessionLoading();
    try {
      state = await _resolve();
      _syncPushSession();
    } on AppError catch (error) {
      if (error.isUnauthenticated) {
        await _tokens.clear();
        state = const SessionLoggedOut(
          notice: 'Your session expired. Please sign in again.',
        );
      } else {
        // Includes the offline case: the tokens are left alone so a retry after
        // signing in again is not the only way back.
        state = SessionLoggedOut(notice: error.uiMessage);
      }
    } catch (_) {
      state = const SessionLoggedOut(notice: 'Could not restore your session.');
    }
  }

  /// Throws [AppError] so the login form can show the failure inline.
  Future<void> login({
    String? tenantCode,
    required String email,
    required String password,
    String? serverUrl,
    String? deviceId,
  }) async {
    if (serverUrl != null && serverUrl.trim().isNotEmpty) {
      await _tokens.setBaseUrl(serverUrl);
    }
    final activeDeviceId = (deviceId != null && deviceId.trim().isNotEmpty)
        ? deviceId.trim()
        : _tokens.deviceId;
    final pair = await _auth.login(
      tenantCode: tenantCode,
      email: email,
      password: password,
      deviceId: activeDeviceId,
    );
    if (!pair.isValid) {
      throw const AppError(
        code: ErrorCodes.unknown,
        message: 'The server did not return a usable session.',
      );
    }
    await _tokens.saveTokens(pair.accessToken, pair.refreshToken);
    await _tokens.rememberLogin(tenantCode?.trim() ?? '', email.trim());
    state = await _resolve();
    _syncPushSession();
  }

  /// Best-effort: hands the session to the native side so it can (re)register
  /// this device's FCM token. Never throws — a push-registration hiccup must
  /// not block sign-in or session restore.
  void _syncPushSession() {
    final accessToken = _tokens.accessToken;
    final deviceId = _tokens.deviceId;
    if (accessToken == null || accessToken.isEmpty) return;
    if (deviceId == null || deviceId.isEmpty) return;
    PushTokenBridge.syncSession(
      baseUrl: _tokens.baseUrl,
      accessToken: accessToken,
      deviceId: deviceId,
    );
  }

  /// No logout endpoint exists — dropping the tokens is the whole operation.
  ///
  /// The state flips first and the keystore is cleared behind it. Waiting on
  /// secure storage before redrawing made the tap feel like it hadn't
  /// registered; there's nothing to wait for, since the app is already treating
  /// the session as gone.
  Future<void> logout() async {
    state = const SessionLoggedOut();
    PushTokenBridge.clearSession();
    await _tokens.clear();
  }

  /// Called by [ApiClient] when a refresh failed and the session is dead.
  void onSessionExpired() {
    state = const SessionLoggedOut(
      notice: 'Your session expired. Please sign in again.',
    );
    PushTokenBridge.clearSession();
  }

  void selectStore(Warehouse warehouse) {
    final current = me;
    if (current == null) return;
    state = SessionReady(
      current.copyWith(warehouseId: warehouse.id, warehouseName: warehouse.name),
    );
  }

  Future<void> refreshMe() async {
    try {
      state = await _resolve();
    } on AppError catch (error) {
      if (error.isUnauthenticated) {
        await _tokens.clear();
        state = const SessionLoggedOut(
          notice: 'Your session expired. Please sign in again.',
        );
      }
      // Any other failure leaves the current session in place.
    }
  }

  /// Loads `/auth/me` and fills in the warehouse if the server didn't.
  ///
  /// Older builds of this API don't include `warehouseId`/`warehouseName` in
  /// `/auth/me` (MOBILE_API_GUIDE.md §3 calls this out as a known gap). In that
  /// case `GET /warehouses` is filtered to the caller's own row, so exactly one
  /// row coming back identifies the store.
  Future<SessionState> _resolve() async {
    var user = await _auth.me();

    if (user.warehouseId != null && user.warehouseName != null) {
      return SessionReady(user);
    }

    List<Warehouse> warehouses = const [];
    try {
      warehouses = await _catalog.warehouses();
    } on AppError catch (error) {
      if (error.isUnauthenticated) rethrow;
      // No WAREHOUSE.VIEW: carry on with whatever /auth/me gave us.
    }

    if (user.warehouseId == null) {
      if (warehouses.length == 1) {
        user = user.copyWith(
          warehouseId: warehouses.first.id,
          warehouseName: warehouses.first.name,
        );
        return SessionReady(user);
      }
      if (warehouses.length > 1) {
        // An unrestricted account (tenant admin) — ask which store to operate.
        return SessionNeedsStore(user, warehouses);
      }
      return SessionReady(user);
    }

    final match = firstWhereOrNull(warehouses, (w) => w.id == user.warehouseId);
    if (match != null) {
      user = user.copyWith(warehouseName: match.name);
    }
    return SessionReady(user);
  }
}
