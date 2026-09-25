import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/json.dart';
import '../api_client.dart';
import '../models/catalog.dart';
import '../models/paged.dart';
import '../models/tenant.dart';

/// Read-only lookups the store screens need to build documents: products,
/// customers, suppliers and the caller's own warehouse row.
///
/// NOTE: `/products`, `/customers` and `/suppliers` are not listed in
/// MOBILE_API_GUIDE.md §5 (which only enumerates the store *transaction*
/// endpoints), but a sale/purchase line needs a productId and a purchase needs
/// a supplierId, so they are assumed to exist with the platform's standard
/// list shape. If a Store Manager role lacks PRODUCT.VIEW / CUSTOMER.VIEW /
/// SUPPLIER.VIEW, these 403 and the affected picker degrades gracefully:
/// the product picker falls back to `/inventory/balance`, which is documented
/// and always in scope.
class CatalogRepository {
  CatalogRepository(this._api);

  final ApiClient _api;

  Future<PagedList<Product>> products({
    int page = 1,
    String? search,
    int pageSize = kPageSize,
    // For a warehouse-scoped account, `/products` is filtered server-side to
    // only products price-listed for that warehouse (see
    // product.service.ts's list()) — fine for a sale, where an unpriced
    // product can't be sold anyway, but wrong for a purchase: acquiring new
    // stock for the first time is exactly the case where it has no retail
    // pricing yet. `all: true` is the escape hatch the server's own schema
    // documents for this ("bypasses warehouse price-list scoping, e.g. for
    // purchase creation") — pass it whenever the picker is choosing what to
    // buy in, not what to sell.
    bool all = false,
  }) async {
    final data = await _api.get('products', query: {
      'page': page,
      'pageSize': pageSize,
      'search': search,
      if (all) 'all': true,
    });
    return PagedList.from(data, Product.fromJson);
  }

  Future<PagedList<Customer>> customers({
    int page = 1,
    String? search,
    int pageSize = kPageSize,
  }) async {
    final data = await _api.get('customers', query: {
      'page': page,
      'pageSize': pageSize,
      'search': search,
    });
    return PagedList.from(data, Customer.fromJson);
  }

  /// One customer by id — used when a document carries `customerId` but the
  /// server didn't expand the relation, so the screen has an id and no name.
  Future<Customer?> customer(String id) async {
    final data = await _api.get('customers/$id');
    final map = asMap(data);
    return map == null ? null : Customer.fromJson(map);
  }

  /// One product by id — used the same way as [customer]: a sale/return/
  /// exchange line carries a `productId` but the server's item payload has no
  /// nested product, so the screen has an id and a placeholder name.
  Future<Product?> product(String id) async {
    final data = await _api.get('products/$id');
    final map = asMap(data);
    return map == null ? null : Product.fromJson(map);
  }

  /// Creates a customer so a walk-in's details can be captured at the till.
  ///
  /// `POST /sales` accepts only a `customerId` — there is no way to attach a
  /// name and phone inline — so recording a walk-in means creating the customer
  /// first and then referencing them. Optional fields are omitted rather than
  /// sent empty, to keep the payload clean for the server's validation.
  Future<Customer> createCustomer({
    required String name,
    String? phone,
    String? email,
    String? customerGroupId,
  }) async {
    final body = <String, dynamic>{'name': name.trim()};
    if ((phone ?? '').trim().isNotEmpty) body['phone'] = phone!.trim();
    if ((email ?? '').trim().isNotEmpty) body['email'] = email!.trim();
    if ((customerGroupId ?? '').isNotEmpty) body['customerGroupId'] = customerGroupId;
    final data = await _api.post('customers', body: body);
    return Customer.fromJson(asMap(data) ?? const {});
  }

  /// Pricing/discount tiers a customer can belong to — gated behind the
  /// CUSTOMER_GROUP plan feature, checked by the caller before showing any
  /// group-selection UI.
  Future<PagedList<CustomerGroup>> customerGroups({
    int page = 1,
    String? search,
    int pageSize = kPageSize,
  }) async {
    final data = await _api.get('customer-groups', query: {
      'page': page,
      'pageSize': pageSize,
      'search': search,
    });
    return PagedList.from(data, CustomerGroup.fromJson);
  }

  Future<PagedList<Supplier>> suppliers({
    int page = 1,
    String? search,
    int pageSize = kPageSize,
  }) async {
    final data = await _api.get('suppliers', query: {
      'page': page,
      'pageSize': pageSize,
      'search': search,
    });
    return PagedList.from(data, Supplier.fromJson);
  }

  /// Filtered server-side to the caller's own row when the account is
  /// warehouse-scoped, so this normally returns exactly one warehouse.
  Future<List<Warehouse>> warehouses() async {
    final data = await _api.get('warehouses', query: {'pageSize': 100});
    return PagedList.from(data, Warehouse.fromJson).items;
  }

  Future<Warehouse?> warehouse(String id) async {
    final data = await _api.get('warehouses/$id');
    final map = asMap(data);
    return map == null ? null : Warehouse.fromJson(map);
  }

  /// The tenant's registered company name and GSTIN, for a receipt header.
  ///
  /// Gated by `TENANT.VIEW` server-side — a warehouse-scoped role may not
  /// hold it. Best-effort: returns null on any error rather than throwing,
  /// so a receipt still prints with just the shop's own name and address.
  Future<TenantProfile?> tenantProfile() async {
    try {
      final data = await _api.get('tenants/me');
      final map = asMap(data);
      return map == null ? null : TenantProfile.fromJson(map);
    } on AppError {
      return null;
    }
  }
}

/// Resolves a real name for every id in [productIds] — best-effort, in
/// parallel, one request per unique id.
///
/// A sale/return/exchange line only ever carries a `productId`; when the
/// server's item payload has no nested product, that id is all a detail
/// screen has to show. A product that 404s or is out of the caller's
/// permission just keeps its placeholder name — this is a display nicety, not
/// something worth failing the whole screen over.
Future<Map<String, String>> resolveProductNames(
  CatalogRepository catalog,
  Iterable<String> productIds,
) async {
  final products = await resolveProducts(catalog, productIds);
  return products.map((id, product) => MapEntry(id, product.name));
}

/// Same idea as [resolveProductNames], but keeps the whole [Product] —
/// for a line that also wants to show a sku or a thumbnail, not just a name.
Future<Map<String, Product>> resolveProducts(
  CatalogRepository catalog,
  Iterable<String> productIds,
) async {
  final ids = productIds.where((id) => id.isNotEmpty).toSet();
  if (ids.isEmpty) return const {};

  final products = <String, Product>{};
  await Future.wait(ids.map((id) async {
    try {
      final product = await catalog.product(id);
      if (product != null) products[id] = product;
    } catch (_) {
      // Best-effort — see doc comment above.
    }
  }));
  return products;
}
