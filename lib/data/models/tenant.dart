import '../../core/json.dart';

/// `GET /tenants/me` — the tenant's registered/legal identity, for documents
/// that need to say who actually sold the goods (a receipt), not just which
/// store it happened at.
///
/// Gated by `TENANT.VIEW`, which a warehouse-scoped role may not hold — every
/// caller of this must treat a fetch failure as "nothing to show", not an
/// error, same as `resolveProducts` in `catalog_repository.dart`.
class TenantProfile {
  const TenantProfile({
    required this.id,
    required this.name,
    this.companyName,
    this.gstNumber,
  });

  final String id;
  final String name;

  /// The registered business name for documents — falls back to [name] (the
  /// tenant's short/display name) when the settings row has none.
  final String? companyName;
  final String? gstNumber;

  factory TenantProfile.fromJson(Map<String, dynamic> json) {
    final settings = asMap(json['settings']);
    final comp = firstString(settings ?? const {}, ['companyName', 'company_name', 'legalName', 'businessName', 'name']) ??
        firstString(json, ['companyName', 'company_name', 'legalName', 'businessName', 'displayName']);
    final gst = firstString(settings ?? const {}, ['gstNumber', 'gst_number', 'gstin', 'gst', 'taxId']) ??
        firstString(json, ['gstNumber', 'gst_number', 'gstin', 'gst', 'taxId']);
    return TenantProfile(
      id: firstString(json, ['id', 'tenantId']) ?? '',
      name: firstString(json, ['name', 'tenantName', 'displayName', 'title']) ?? 'Tenant',
      companyName: comp,
      gstNumber: gst,
    );
  }

  /// What to print on a receipt — the registered company name when set,
  /// otherwise the tenant's plain name.
  String get displayName => (companyName ?? '').isNotEmpty ? companyName! : name;
}
