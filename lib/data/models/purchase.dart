import '../../core/json.dart';

class PurchaseItem {
  const PurchaseItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    this.sku,
    this.receivedQuantity,
    this.lineTotal,
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final double price;
  final String? sku;
  final double? receivedQuantity;
  final double? lineTotal;

  factory PurchaseItem.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    return PurchaseItem(
      id: firstString(json, ['id', 'purchaseItemId']) ?? '',
      productId:
          firstString(json, ['productId']) ?? asString(product?['id']) ?? '',
      productName: firstString(json, ['productName', 'name']) ??
          asString(product?['name']) ??
          'Item',
      sku: firstString(json, ['sku']) ?? asString(product?['sku']),
      quantity: asDouble(firstOf(json, ['quantity', 'qty', 'orderedQuantity'])),
      price: asDouble(firstOf(json, ['price', 'unitPrice', 'cost', 'rate'])),
      receivedQuantity:
          asDoubleOrNull(firstOf(json, ['receivedQuantity', 'receivedQty'])),
      lineTotal:
          asDoubleOrNull(firstOf(json, ['lineTotal', 'total', 'totalAmount'])),
    );
  }

  double get amount => lineTotal ?? quantity * price;

  double get pendingQuantity {
    final left = quantity - (receivedQuantity ?? 0);
    return left < 0 ? 0 : left;
  }
}

class Purchase {
  const Purchase({
    required this.id,
    required this.status,
    this.number,
    this.supplierId,
    this.supplierName,
    this.warehouseId,
    this.purchaseDate,
    this.expectedDate,
    this.totalAmount,
    this.notes,
    this.items = const [],
    this.createdAt,
  });

  final String id;
  final String status;
  final String? number;
  final String? supplierId;
  final String? supplierName;
  final String? warehouseId;
  final String? purchaseDate;
  final String? expectedDate;
  final double? totalAmount;
  final String? notes;
  final List<PurchaseItem> items;
  final String? createdAt;

  factory Purchase.fromJson(Map<String, dynamic> json) {
    final supplier = asMap(json['supplier']);
    return Purchase(
      id: firstString(json, ['id', 'purchaseId']) ?? '',
      status: firstString(json, ['status', 'state']) ?? 'DRAFT',
      number: firstString(json, ['purchaseNumber', 'number', 'code', 'poNumber']),
      supplierId:
          firstString(json, ['supplierId']) ?? asString(supplier?['id']),
      supplierName:
          firstString(json, ['supplierName']) ?? asString(supplier?['name']),
      warehouseId: firstString(json, ['warehouseId']),
      purchaseDate: firstString(json, ['purchaseDate', 'orderDate', 'date']),
      expectedDate: firstString(json, ['expectedDate', 'expectedDeliveryDate']),
      totalAmount: asDoubleOrNull(
        firstOf(json, ['totalAmount', 'total', 'grandTotal', 'netAmount']),
      ),
      notes: firstString(json, ['notes', 'note', 'remarks']),
      items: asMapList(json['items'] ?? json['purchaseItems'])
          .map(PurchaseItem.fromJson)
          .toList(),
      createdAt: firstString(json, ['createdAt', 'created_at']),
    );
  }

  String get label => number != null ? 'Purchase $number' : 'Purchase #$id';

  double get computedTotal =>
      totalAmount ?? items.fold<double>(0, (sum, item) => sum + item.amount);

  bool get hasPendingReceipt =>
      items.isEmpty || items.any((item) => item.pendingQuantity > 0);
}

class PurchaseReturnItem {
  const PurchaseReturnItem({
    required this.productName,
    required this.quantity,
    this.purchaseItemId,
    this.amount,
  });

  final String productName;
  final double quantity;
  final String? purchaseItemId;
  final double? amount;

  factory PurchaseReturnItem.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    return PurchaseReturnItem(
      productName: firstString(json, ['productName', 'name']) ??
          asString(product?['name']) ??
          'Item',
      quantity: asDouble(firstOf(json, ['quantity', 'qty'])),
      purchaseItemId: firstString(json, ['purchaseItemId']),
      amount: asDoubleOrNull(
        firstOf(json, ['amount', 'lineTotal', 'total', 'refundAmount']),
      ),
    );
  }
}

class PurchaseReturn {
  const PurchaseReturn({
    required this.id,
    this.number,
    this.purchaseId,
    this.purchaseNumber,
    this.reason,
    this.status,
    this.totalAmount,
    this.items = const [],
    this.createdAt,
  });

  final String id;
  final String? number;
  final String? purchaseId;
  final String? purchaseNumber;
  final String? reason;
  final String? status;
  final double? totalAmount;
  final List<PurchaseReturnItem> items;
  final String? createdAt;

  factory PurchaseReturn.fromJson(Map<String, dynamic> json) {
    final purchase = asMap(json['purchase']);
    return PurchaseReturn(
      id: firstString(json, ['id']) ?? '',
      number: firstString(json, ['returnNumber', 'number', 'code']),
      purchaseId:
          firstString(json, ['purchaseId']) ?? asString(purchase?['id']),
      purchaseNumber: firstString(json, ['purchaseNumber']) ??
          asString(firstOf(purchase ?? {}, ['purchaseNumber', 'number'])),
      reason: asString(json['reason']),
      status: asString(json['status']),
      totalAmount: asDoubleOrNull(
        firstOf(json, ['totalAmount', 'total', 'refundAmount']),
      ),
      items: asMapList(json['items'] ?? json['returnItems'])
          .map(PurchaseReturnItem.fromJson)
          .toList(),
      createdAt: firstString(json, ['createdAt', 'created_at']),
    );
  }

  String get label =>
      number != null ? 'Purchase return $number' : 'Purchase return #$id';
}
