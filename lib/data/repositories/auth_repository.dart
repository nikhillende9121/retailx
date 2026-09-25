import '../../core/json.dart';
import '../api_client.dart';
import '../models/auth.dart';

class AuthRepository {
  AuthRepository(this._api);

  final ApiClient _api;

  /// [tenantCode] is optional if tenant is auto-resolved server-side.
  Future<TokenPair> login({
    String? tenantCode,
    required String email,
    required String password,
    String? deviceId,
  }) async {
    final body = <String, dynamic>{
      'email': email.trim(),
      'password': password,
    };
    if (tenantCode != null && tenantCode.trim().isNotEmpty) {
      body['tenantCode'] = tenantCode.trim();
    }
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      body['deviceId'] = deviceId.trim();
    }
    final data = await _api.post('auth/login', body: body);
    return TokenPair.fromJson(asMap(data) ?? const {});
  }

  Future<Me> me() async {
    final data = await _api.get('auth/me');
    return Me.fromJson(asMap(data) ?? const {});
  }
}
