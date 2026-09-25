import '../../core/json.dart';
import '../token_store.dart' show absoluteUrl;

class Product {
  const Product({
    required this.id,
    required this.name,
    this.sku,
    this.barcode,
    this.unit,
    this.defaultPrice,
    this.imageUrl,
  });

  final String id;
  final String name;
  final String? sku;
  final String? barcode;
  final String? unit;

  /// Price the API reports for this product, when it reports one.
  ///
  /// `/inventory/balance` does return a `price` per row, so the till can prefill
  /// the line and the cashier only types when overriding it. The sale endpoint
  /// still takes whatever price is submitted — this is a convenience, not an
  /// authority.
  final double? defaultPrice;

  /// Resolved to an absolute URL at parse time, since `images` entries can be
  /// server-relative paths.
  final String? imageUrl;

  factory Product.fromJson(Map<String, dynamic> json) => Product(
        id: firstString(json, ['id', 'productId']) ?? '',
        name: firstString(json, ['name', 'productName', 'title']) ?? 'Unnamed product',
        sku: firstString(json, ['sku', 'code', 'productSku']),
        barcode: firstString(json, ['barcode', 'ean', 'productBarcode']),
        unit: firstString(json, ['unit', 'uom', 'unitName']),
        defaultPrice: asDoubleOrNull(
          firstOf(json, ['sellingPrice', 'price', 'mrp', 'unitPrice']),
        ),
        imageUrl: absoluteUrl(
          firstImageUrl(json['images']) ??
              firstString(json, ['imageUrl', 'image', 'thumbnail']),
        ),
      );

  String get subtitle {
    final parts = <String>[];
    if (sku != null) parts.add(sku!);
    if (unit != null) parts.add(unit!);
    return parts.join(' · ');
  }

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return name.toLowerCase().contains(q) ||
        (sku ?? '').toLowerCase().contains(q) ||
        (barcode ?? '').toLowerCase().contains(q);
  }
}

class CustomerGroup {
  const CustomerGroup({required this.id, required this.name, this.code});

  final String id;
  final String name;
  final String? code;

  factory CustomerGroup.fromJson(Map<String, dynamic> json) => CustomerGroup(
        id: firstString(json, ['id', 'customerGroupId']) ?? '',
        name: firstString(json, ['name', 'groupName']) ?? 'Group',
        code: firstString(json, ['code']),
      );
}

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.customerGroupId,
    this.customerGroupName,
  });

  final String id;
  final String name;
  final String? phone;
  final String? email;

  /// The pricing/discount tier this customer belongs to — see `PriceList`
  /// and `Discount`'s `customerGroupId` scoping on the backend. Only
  /// meaningful when the tenant's plan has CUSTOMER_GROUP enabled.
  final String? customerGroupId;
  final String? customerGroupName;

  factory Customer.fromJson(Map<String, dynamic> json) {
    final nameStr = firstString(json, ['name', 'customerName', 'fullName', 'displayName', 'title']);
    final first = firstString(json, ['firstName', 'first_name']);
    final last = firstString(json, ['lastName', 'last_name']);
    final combinedName = (first != null || last != null)
        ? [first, last].whereType<String>().join(' ').trim()
        : null;
    final name = nameStr ?? (combinedName?.isNotEmpty == true ? combinedName : null) ?? 'Walk-in';
    final group = asMap(json['customerGroup']);

    return Customer(
      id: firstString(json, ['id', 'customerId']) ?? '',
      name: name,
      phone: firstString(json, ['phone', 'mobile', 'contactNumber', 'phoneNumber', 'phone_number']),
      email: firstString(json, ['email', 'emailAddress', 'email_address']),
      customerGroupId:
          firstString(json, ['customerGroupId']) ?? asString(group?['id']),
      customerGroupName: firstString(json, ['customerGroupName']) ??
          asString(group?['name']),
    );
  }

  String get subtitle => [phone, email].whereType<String>().join(' · ');
}

class Supplier {
  const Supplier({required this.id, required this.name, this.phone});

  final String id;
  final String name;
  final String? phone;

  factory Supplier.fromJson(Map<String, dynamic> json) => Supplier(
        id: firstString(json, ['id', 'supplierId']) ?? '',
        name: firstString(json, ['name', 'supplierName']) ?? 'Supplier',
        phone: firstString(json, ['phone', 'mobile', 'contactNumber']),
      );
}

class Warehouse {
  const Warehouse({required this.id, required this.name, this.code, this.address});

  final String id;
  final String name;
  final String? code;
  final String? address;

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    final addrVal = json['address'];
    String? parsedAddress;
    if (addrVal is String && addrVal.trim().isNotEmpty) {
      parsedAddress = addrVal.trim();
    } else if (addrVal is Map) {
      final addrMap = asMap(addrVal);
      final parts = <String>[];
      final line1 = firstString(addrMap ?? const {}, ['line1', 'addressLine1', 'street', 'address']);
      final line2 = firstString(addrMap ?? const {}, ['line2', 'addressLine2']);
      final city = firstString(addrMap ?? const {}, ['city', 'town']);
      final state = firstString(addrMap ?? const {}, ['state', 'province']);
      final postal = firstString(addrMap ?? const {}, ['postalCode', 'zipCode', 'pincode', 'pin']);
      if (line1 != null) parts.add(line1);
      if (line2 != null) parts.add(line2);
      if (city != null) parts.add(city);
      if (state != null) parts.add(state);
      if (postal != null) parts.add(postal);
      if (parts.isNotEmpty) parsedAddress = parts.join(', ');
    }
    if (parsedAddress == null || parsedAddress.isEmpty) {
      parsedAddress = firstString(json, [
        'location',
        'city',
        'fullAddress',
        'storeAddress',
        'addressLine1',
        'street',
      ]);
    }
    return Warehouse(
      id: firstString(json, ['id', 'warehouseId']) ?? '',
      name: firstString(json, ['name', 'warehouseName', 'storeName', 'title']) ?? 'Store',
      code: firstString(json, ['code', 'warehouseCode']),
      address: parsedAddress,
    );
  }

  String get subtitle => [code, address].whereType<String>().join(' · ');
}
