import '../../core/json.dart';
import '../token_store.dart' show absoluteUrl;

class TokenPair {
  const TokenPair({required this.accessToken, required this.refreshToken});

  final String accessToken;
  final String refreshToken;

  factory TokenPair.fromJson(Map<String, dynamic> json) => TokenPair(
        accessToken: asString(json['accessToken']) ?? '',
        refreshToken: asString(json['refreshToken']) ?? '',
      );

  bool get isValid => accessToken.isNotEmpty && refreshToken.isNotEmpty;
}

/// `GET /auth/me` — the signed-in user, their role, what they may do, what the
/// tenant's plan includes, and which single store they operate.
class Me {
  const Me({
    required this.id,
    required this.name,
    required this.email,
    this.tenantId,
    this.tenantName,
    this.tenantCode,
    this.tenantLogo,
    this.warehouseId,
    this.warehouseName,
    this.warehouseCode,
    this.warehouseAddress,
    this.warehousePhone,
    this.roleName,
    this.permissions = const [],
    this.features = const [],
  });

  final String id;
  final String name;
  final String email;
  final String? tenantId;
  final String? tenantName;
  final String? tenantCode;
  final String? tenantLogo;
  final String? warehouseId;
  final String? warehouseName;
  final String? warehouseCode;
  final String? warehouseAddress;
  final String? warehousePhone;
  final String? roleName;
  final List<String> permissions;
  final List<String> features;

  factory Me.fromJson(Map<String, dynamic> json) {
    final role = asMap(json['role']);
    final warehouse = asMap(json['warehouse']);
    final tenant = asMap(json['tenant']);
    return Me(
      id: asString(json['id']) ?? '',
      name: firstString(json, ['name', 'fullName', 'email']) ?? 'User',
      email: asString(json['email']) ?? '',
      tenantId: firstString(json, ['tenantId', 'tenant_id']) ??
          asString(tenant?['id']),
      tenantName: firstString(json, ['tenantName', 'tenant_name']) ??
          asString(tenant?['name']),
      tenantCode: firstString(json, ['tenantCode', 'tenant_code']) ??
          asString(tenant?['code']),
      tenantLogo: absoluteUrl(
        firstString(json, ['tenantLogo', 'logo', 'logoUrl']) ??
            asString(tenant?['logo']) ??
            asString(tenant?['logoUrl']),
      ),
      warehouseId: firstString(json, ['warehouseId', 'warehouse_id']) ??
          asString(warehouse?['id']),
      warehouseName: firstString(json, ['warehouseName', 'warehouse_name']) ??
          asString(warehouse?['name']),
      warehouseCode: firstString(json, ['warehouseCode', 'warehouse_code']) ??
          asString(warehouse?['code']),
      warehouseAddress: firstString(json, ['warehouseAddress', 'warehouse_address']) ??
          (warehouse?['address'] is String
              ? asString(warehouse?['address'])
              : firstString(warehouse ?? const {}, ['location', 'fullAddress', 'addressLine1', 'street', 'city'])),
      warehousePhone: firstString(json, ['warehousePhone', 'phone']) ??
          asString(warehouse?['phone']),
      roleName: asString(role?['name']) ?? firstString(json, ['roleName']),
      permissions: asStringList(json['permissions']),
      features: asStringList(
        json['enabledFeatures'] ?? json['features'] ?? json['enabled_features'],
      ),
    );
  }

  /// True when the role holds [permission]. Advisory only — the server
  /// re-checks every request; this just avoids offering an action that 403s.
  bool can(String permission) => permissions.contains(permission);

  bool canAny(List<String> anyOf) => anyOf.any(permissions.contains);

  /// True when the tenant's plan includes [feature].
  ///
  /// If the server didn't send `enabledFeatures` at all we must not hide the
  /// whole app — treat an empty list as "unknown, allow and let the API decide".
  bool hasFeature(String feature) =>
      features.isEmpty || features.contains(feature);

  bool get isWarehouseScoped => (warehouseId ?? '').isNotEmpty;

  String get storeLabel {
    final name = warehouseName;
    if (name != null && name.isNotEmpty) return name;
    final id = warehouseId;
    if (id != null && id.isNotEmpty) return 'Store #$id';
    return 'All stores';
  }

  Me copyWith({
    String? warehouseId,
    String? warehouseName,
    String? warehouseCode,
    String? warehouseAddress,
    String? warehousePhone,
    List<String>? features,
  }) =>
      Me(
        id: id,
        name: name,
        email: email,
        tenantId: tenantId,
        tenantName: tenantName,
        tenantCode: tenantCode,
        tenantLogo: tenantLogo,
        warehouseId: warehouseId ?? this.warehouseId,
        warehouseName: warehouseName ?? this.warehouseName,
        warehouseCode: warehouseCode ?? this.warehouseCode,
        warehouseAddress: warehouseAddress ?? this.warehouseAddress,
        warehousePhone: warehousePhone ?? this.warehousePhone,
        roleName: roleName,
        permissions: permissions,
        features: features ?? this.features,
      );
}

