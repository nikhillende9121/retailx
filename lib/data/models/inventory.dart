import '../../core/json.dart';
import '../token_store.dart' show absoluteUrl;
import 'catalog.dart';

/// A row of `GET /inventory/balance` — product plus on-hand quantity for the
/// caller's own store.
class StockBalance {
  const StockBalance({
    required this.productId,
    required this.productName,
    required this.quantity,
    this.sku,
    this.barcode,
    this.unit,
    this.reservedQuantity,
    this.defaultPrice,
    this.imageUrl,
  });

  final String productId;
  final String productName;
  final double quantity;
  final String? sku;
  final String? barcode;
  final String? unit;
  final double? reservedQuantity;
  final double? defaultPrice;
  final String? imageUrl;

  factory StockBalance.fromJson(Map<String, dynamic> json) {
    // `/inventory/balance` nests the whole product and puts `price` on the row:
    //   { warehouseId, productId, quantity, price, product: { name, sku, images } }
    final product = asMap(json['product']);
    return StockBalance(
      productId: firstString(json, ['productId', 'product_id']) ??
          asString(product?['id']) ??
          '',
      productName: firstString(json, ['productName', 'name']) ??
          asString(product?['name']) ??
          'Unnamed product',
      sku: firstString(json, ['sku']) ?? asString(product?['sku']),
      barcode: firstString(json, ['barcode', 'ean', 'productBarcode']) ??
          firstString(product ?? {}, ['barcode', 'ean', 'productBarcode']),
      unit: firstString(json, ['unit', 'uom']) ?? asString(product?['unit']),
      quantity: asDouble(
        firstOf(json, ['quantity', 'availableQuantity', 'onHand', 'balance']),
      ),
      reservedQuantity:
          asDoubleOrNull(firstOf(json, ['reservedQuantity', 'reserved'])),
      defaultPrice: asDoubleOrNull(
        firstOf(json, ['sellingPrice', 'price', 'mrp']) ??
            firstOf(product ?? {}, ['sellingPrice', 'price', 'mrp']),
      ),
      imageUrl: absoluteUrl(
        firstImageUrl(product?['images'] ?? json['images']) ??
            firstString(json, ['imageUrl', 'image']),
      ),
    );
  }

  /// Lets a balance row stand in for a catalogue product on the till grid.
  Product get product => Product(
        id: productId,
        name: productName,
        sku: sku,
        barcode: barcode,
        unit: unit,
        defaultPrice: defaultPrice,
        imageUrl: imageUrl,
      );

  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return productName.toLowerCase().contains(q) ||
        (sku ?? '').toLowerCase().contains(q) ||
        (barcode ?? '').toLowerCase().contains(q);
  }

  bool get inStock => quantity > 0;
}

class StockTransferItem {
  const StockTransferItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    this.sku,
    this.imageUrl,
    this.approvedQuantity,
    this.shippedQuantity,
    this.receivedQuantity,
  });

  /// The transfer *line* id — what `stockTransferItemId` means to
  /// `/ship` and `/receive`, distinct from [productId].
  final String id;
  final String productId;
  final String productName;

  /// Requested quantity, i.e. what was asked for at create time.
  final double quantity;
  final String? sku;
  final String? imageUrl;

  /// Set once a tenant admin approves the transfer — this is how much
  /// `/ship` is allowed to move out.
  final double? approvedQuantity;

  /// Set once the source store ships it — this is how much `/receive` is
  /// allowed to book in.
  final double? shippedQuantity;
  final double? receivedQuantity;

  factory StockTransferItem.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    return StockTransferItem(
      id: firstString(json, ['id']) ?? '',
      productId:
          firstString(json, ['productId']) ?? asString(product?['id']) ?? '',
      productName: firstString(json, ['productName', 'name']) ??
          asString(product?['name']) ??
          'Item',
      sku: firstString(json, ['sku']) ?? asString(product?['sku']),
      imageUrl: absoluteUrl(
        firstImageUrl(product?['images'] ?? json['images']) ??
            firstString(json, ['imageUrl', 'image']),
      ),
      quantity: asDouble(
        firstOf(json, ['requestedQuantity', 'quantity', 'qty']),
      ),
      approvedQuantity: asDoubleOrNull(json['approvedQuantity']),
      shippedQuantity: asDoubleOrNull(json['shippedQuantity']),
      receivedQuantity: asDoubleOrNull(json['receivedQuantity']),
    );
  }

  /// Every quantity stage that has actually happened yet, in order —
  /// "Requested" always, "Approved"/"Shipped"/"Received" only once the
  /// server has set them, so a still-DRAFT line doesn't show two dashes.
  List<(String, double)> get quantityStages => [
        ('Requested', quantity),
        if (approvedQuantity != null) ('Approved', approvedQuantity!),
        if (shippedQuantity != null) ('Shipped', shippedQuantity!),
        if (receivedQuantity != null) ('Received', receivedQuantity!),
      ];

  /// True when the server sent only a `productId` and this line is still
  /// carrying the generic fallback name — `/stock-transfers` doesn't expand
  /// the product relation, so this is normally every line.
  bool get needsProductLookup => productId.isNotEmpty && productName == 'Item';

  /// A copy carrying the name/sku/image from a separate product lookup.
  StockTransferItem withProduct(Product product) => StockTransferItem(
        id: id,
        productId: productId,
        productName: product.name,
        quantity: quantity,
        sku: product.sku,
        imageUrl: product.imageUrl,
        approvedQuantity: approvedQuantity,
        shippedQuantity: shippedQuantity,
        receivedQuantity: receivedQuantity,
      );
}

class StockTransfer {
  const StockTransfer({
    required this.id,
    required this.status,
    this.number,
    this.fromWarehouseId,
    this.fromWarehouseName,
    this.fromWarehouseCode,
    this.toWarehouseId,
    this.toWarehouseName,
    this.toWarehouseCode,
    this.transferDate,
    this.notes,
    this.items = const [],
    this.createdAt,
  });

  final String id;
  final String status;
  final String? number;
  final String? fromWarehouseId;
  final String? fromWarehouseName;
  final String? fromWarehouseCode;
  final String? toWarehouseId;
  final String? toWarehouseName;
  final String? toWarehouseCode;
  final String? transferDate;
  final String? notes;
  final List<StockTransferItem> items;
  final String? createdAt;

  factory StockTransfer.fromJson(Map<String, dynamic> json) {
    final from = asMap(json['fromWarehouse']);
    final to = asMap(json['toWarehouse']);
    return StockTransfer(
      id: firstString(json, ['id']) ?? '',
      status: firstString(json, ['status', 'state']) ?? 'DRAFT',
      number: firstString(json, ['transferNumber', 'number', 'code']),
      fromWarehouseId:
          firstString(json, ['fromWarehouseId']) ?? asString(from?['id']),
      fromWarehouseName: firstString(json, ['fromWarehouseName']) ??
          asString(from?['name']),
      fromWarehouseCode: asString(from?['code']),
      toWarehouseId:
          firstString(json, ['toWarehouseId']) ?? asString(to?['id']),
      toWarehouseName:
          firstString(json, ['toWarehouseName']) ?? asString(to?['name']),
      toWarehouseCode: asString(to?['code']),
      transferDate: firstString(json, ['transferDate', 'date']),
      notes: firstString(json, ['notes', 'note', 'remarks']),
      items: asMapList(json['items'] ?? json['transferItems'])
          .map(StockTransferItem.fromJson)
          .toList(),
      createdAt: firstString(json, ['createdAt', 'created_at']),
    );
  }

  String get label => number != null ? 'Transfer $number' : 'Transfer #$id';

  /// The backend's `/stock-transfers` list ignores the `search` query param
  /// entirely (it always returns the tenant's whole unpaginated list), so
  /// the search box only works via this client-side filter over what's
  /// already been fetched — see `TransfersScreen`'s `where`.
  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return (number ?? '').toLowerCase().contains(q) ||
        id.toLowerCase().contains(q) ||
        (fromWarehouseName ?? '').toLowerCase().contains(q) ||
        (toWarehouseName ?? '').toLowerCase().contains(q) ||
        (fromWarehouseCode ?? '').toLowerCase().contains(q) ||
        (toWarehouseCode ?? '').toLowerCase().contains(q);
  }

  String fromLabel() => fromWarehouseName ?? 'Store ${fromWarehouseId ?? '—'}';

  String toLabel() => toWarehouseName ?? 'Store ${toWarehouseId ?? '—'}';

  /// Outgoing when this store is the source — drives which lifecycle action
  /// (ship vs receive) is offered.
  bool isOutgoing(String? myWarehouseId) =>
      myWarehouseId != null && fromWarehouseId == myWarehouseId;

  double get totalQuantity =>
      items.fold<double>(0, (sum, item) => sum + item.quantity);

  bool get needsItemProductLookup => items.any((item) => item.needsProductLookup);

  StockTransfer withItems(List<StockTransferItem> items) => StockTransfer(
        id: id,
        status: status,
        number: number,
        fromWarehouseId: fromWarehouseId,
        fromWarehouseName: fromWarehouseName,
        fromWarehouseCode: fromWarehouseCode,
        toWarehouseId: toWarehouseId,
        toWarehouseName: toWarehouseName,
        toWarehouseCode: toWarehouseCode,
        transferDate: transferDate,
        notes: notes,
        items: items,
        createdAt: createdAt,
      );
}
