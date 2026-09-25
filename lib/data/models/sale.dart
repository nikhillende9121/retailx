import '../../core/formatters.dart' show parseDate;
import '../../core/json.dart';
import 'catalog.dart';

/// One user eligible to be assigned a sale for delivery — from `GET
/// /sales/delivery-assignees`, gated by `SALE.SHIP` (whoever can ship a
/// sale can see who it could be assigned to), not `USER.VIEW`.
class DeliveryAssignee {
  const DeliveryAssignee({required this.id, required this.name});

  final String id;
  final String name;

  factory DeliveryAssignee.fromJson(Map<String, dynamic> json) =>
      DeliveryAssignee(
        id: firstString(json, ['id']) ?? '',
        name: firstString(json, ['name']) ?? 'User',
      );
}

/// One GST component on a sale line — CGST+SGST for an intra-state sale,
/// IGST for inter-state, plus an extra CESS row when the resolved tax rate
/// carries one. `GET /sales/:id` sends these as a flat list per item, not a
/// single blended rate.
class SaleItemTax {
  const SaleItemTax({
    required this.component,
    required this.ratePercent,
    required this.amount,
    this.taxRateId,
  });

  final String? taxRateId;
  final String component;
  final double ratePercent;
  final double amount;

  factory SaleItemTax.fromJson(Map<String, dynamic> json) => SaleItemTax(
        taxRateId: asString(json['taxRateId']),
        component: asString(json['component']) ?? '',
        ratePercent: asDouble(json['ratePercent']),
        amount: asDouble(json['amount']),
      );
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.price,
    this.sku,
    this.lineTotal,
    this.returnedQuantity,
    this.tax = 0,
    this.taxes = const [],
  });

  final String id;
  final String productId;
  final String productName;
  final double quantity;
  final double price;
  final String? sku;
  final double? lineTotal;

  /// Populated by some responses; used to cap what a return may claim.
  final double? returnedQuantity;

  /// Total tax on this line — the sum of [taxes], already computed
  /// server-side.
  final double tax;

  /// The CGST/SGST/IGST/CESS breakdown that sums to [tax].
  final List<SaleItemTax> taxes;

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    return SaleItem(
      id: firstString(json, ['id', 'saleItemId']) ?? '',
      productId: firstString(json, ['productId', 'product_id']) ??
          asString(product?['id']) ??
          '',
      productName: firstString(json, ['productName', 'name']) ??
          asString(product?['name']) ??
          'Item',
      sku: firstString(json, ['sku']) ?? asString(product?['sku']),
      quantity: asDouble(firstOf(json, ['quantity', 'qty'])),
      price: asDouble(firstOf(json, ['price', 'unitPrice', 'rate'])),
      lineTotal: asDoubleOrNull(
        firstOf(json, ['lineTotal', 'total', 'totalAmount', 'subtotal']),
      ),
      returnedQuantity:
          asDoubleOrNull(firstOf(json, ['returnedQuantity', 'returnedQty'])),
      tax: asDouble(json['tax']),
      taxes: asMapList(json['taxes']).map(SaleItemTax.fromJson).toList(),
    );
  }

  /// Pre-tax line amount.
  double get amount => lineTotal ?? quantity * price;

  /// Line amount including its own tax.
  double get amountWithTax => amount + tax;

  /// Quantity still eligible to be returned or exchanged.
  double get availableToReturn {
    final already = returnedQuantity ?? 0;
    final left = quantity - already;
    return left < 0 ? 0 : left;
  }

  /// True when the server sent only a `productId` and this line is still
  /// carrying the generic fallback name.
  bool get needsProductLookup => productId.isNotEmpty && productName == 'Item';

  /// A copy carrying the name from a separate product lookup.
  SaleItem withProductName(String name) => SaleItem(
        id: id,
        productId: productId,
        productName: name,
        quantity: quantity,
        price: price,
        sku: sku,
        lineTotal: lineTotal,
        returnedQuantity: returnedQuantity,
        tax: tax,
        taxes: taxes,
      );
}

/// A discount applied to a sale — a line-level manual/catalog discount when
/// [saleItemId] is set, an order-level discount or coupon otherwise. `GET
/// /sales/:id` gives no name for it, only the id of whichever [Discount] or
/// [Coupon] resource produced it.
class SaleDiscount {
  const SaleDiscount({
    required this.id,
    required this.amount,
    this.saleItemId,
    this.discountId,
    this.couponId,
  });

  final String id;
  final String? saleItemId;
  final String? discountId;
  final String? couponId;
  final double amount;

  bool get isLineLevel => (saleItemId ?? '').isNotEmpty;
  bool get isCoupon => (couponId ?? '').isNotEmpty;

  factory SaleDiscount.fromJson(Map<String, dynamic> json) => SaleDiscount(
        id: asString(json['id']) ?? '',
        saleItemId: asString(json['saleItemId']),
        discountId: asString(json['discountId']),
        couponId: asString(json['couponId']),
        amount: asDouble(json['amount']),
      );
}

/// An invoice-level charge — shipping, packing, handling — snapshotted onto
/// the sale from an extra-charge catalog entry. Not a tax; [taxAmount] is the
/// tax charged on top of it.
class SaleCharge {
  const SaleCharge({
    required this.id,
    required this.name,
    required this.amount,
    required this.taxAmount,
  });

  final String id;
  final String name;
  final double amount;
  final double taxAmount;

  double get total => amount + taxAmount;

  factory SaleCharge.fromJson(Map<String, dynamic> json) => SaleCharge(
        id: asString(json['id']) ?? '',
        name: asString(json['name']) ?? 'Charge',
        amount: asDouble(json['amount']),
        taxAmount: asDouble(json['taxAmount']),
      );
}

class Sale {
  const Sale({
    required this.id,
    required this.status,
    this.number,
    this.channel,
    this.saleDate,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    this.warehouseId,
    this.warehouseName,
    this.items = const [],
    this.discounts = const [],
    this.charges = const [],
    this.subtotal,
    this.taxAmount,
    this.totalAmount,
    this.assignedDeliveryUserId,
    this.assignedDeliveryUserName,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String status;
  final String? number;
  final String? channel;
  final String? saleDate;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final String? warehouseId;
  final String? warehouseName;
  final List<SaleItem> items;

  /// Line- and order-level discounts, including redeemed coupons.
  final List<SaleDiscount> discounts;

  /// Invoice-level charges (shipping, packing, handling).
  final List<SaleCharge> charges;
  final double? subtotal;
  final double? taxAmount;
  final double? totalAmount;

  /// Who this sale is assigned to for delivery — set by `POST
  /// .../ship` (which now requires an assignee) and null until then, or
  /// forever for a sale shipped before this feature existed. Once set, only
  /// this user (or a `SALE.UPDATE` holder) can deliver it — see
  /// `transitionsFor`'s `deliver` gating in `sale_detail_screen.dart`.
  final String? assignedDeliveryUserId;
  final String? assignedDeliveryUserName;
  final String? createdAt;
  final String? updatedAt;

  factory Sale.fromJson(Map<String, dynamic> json) {
    final customer = asMap(json['customer']);
    final warehouse = asMap(json['warehouse']);

    final custNameStr = firstString(json, ['customerName']) ??
        firstString(customer ?? const {}, ['name', 'fullName', 'customerName', 'displayName', 'title']);
    final custFirst = firstString(customer ?? const {}, ['firstName', 'first_name']);
    final custLast = firstString(customer ?? const {}, ['lastName', 'last_name']);
    final combinedCustName = (custFirst != null || custLast != null)
        ? [custFirst, custLast].whereType<String>().join(' ').trim()
        : null;
    final custName = custNameStr ?? (combinedCustName?.isNotEmpty == true ? combinedCustName : null);

    final custPhone = firstString(json, ['customerPhone', 'phone', 'mobile']) ??
        firstString(customer ?? const {}, ['phone', 'mobile', 'contactNumber', 'phone_number', 'phoneNumber']);

    final custEmail = firstString(json, ['customerEmail', 'email']) ??
        firstString(customer ?? const {}, ['email', 'emailAddress', 'email_address']);

    final whName = firstString(json, ['warehouseName']) ??
        firstString(warehouse ?? const {}, ['name', 'warehouseName', 'storeName', 'title']);

    return Sale(
      id: firstString(json, ['id', 'saleId']) ?? '',
      status: firstString(json, ['status', 'state']) ?? 'DRAFT',
      number: firstString(json, ['saleNumber', 'number', 'code', 'invoiceNumber']),
      channel: asString(json['channel']),
      saleDate: firstString(json, ['saleDate', 'date', 'created_at', 'createdAt']),
      customerId: firstString(json, ['customerId']) ?? asString(customer?['id']),
      customerName: custName?.isNotEmpty == true ? custName : null,
      customerPhone: custPhone?.isNotEmpty == true ? custPhone : null,
      customerEmail: custEmail?.isNotEmpty == true ? custEmail : null,
      warehouseId:
          firstString(json, ['warehouseId']) ?? asString(warehouse?['id']),
      warehouseName: whName?.isNotEmpty == true ? whName : null,
      items: asMapList(json['items'] ?? json['saleItems'])
          .map(SaleItem.fromJson)
          .toList(),
      discounts:
          asMapList(json['discounts']).map(SaleDiscount.fromJson).toList(),
      charges: asMapList(json['charges']).map(SaleCharge.fromJson).toList(),
      subtotal: asDoubleOrNull(firstOf(json, ['subtotal', 'subTotal', 'itemsSubtotal'])),
      taxAmount: asDoubleOrNull(firstOf(json, ['taxAmount', 'tax', 'taxTotal', 'totalTax'])),
      totalAmount: asDoubleOrNull(firstOf(json, ['totalAmount', 'total', 'grandTotal', 'total_amount'])),
      assignedDeliveryUserId: firstString(json, ['assignedDeliveryUserId']),
      assignedDeliveryUserName: firstString(json, ['assignedDeliveryUserName']),
      createdAt: firstString(json, ['createdAt', 'created_at']),
      updatedAt: firstString(json, ['updatedAt', 'updated_at']),
    );
  }

  String get label => number != null ? 'Sale $number' : 'Sale #$id';

  /// The backend's `/sales` list ignores the `search` query param entirely
  /// (it only understands `status`/`channel`, and always returns the
  /// tenant's whole unpaginated list otherwise), so the search box only
  /// works via this client-side filter over what's already been fetched —
  /// see `SalesListScreen`'s `where`.
  bool matches(String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase();
    return (number ?? '').toLowerCase().contains(q) ||
        id.toLowerCase().contains(q) ||
        (customerName ?? '').toLowerCase().contains(q) ||
        (customerPhone ?? '').toLowerCase().contains(q) ||
        (customerEmail ?? '').toLowerCase().contains(q);
  }

  /// What to show for the customer.
  ///
  /// The create response doesn't always expand the customer relation, so a sale
  /// can come back with an id and no name. Showing "Customer #12" is honest;
  /// showing "Walk-in" would claim the sale was anonymous when it wasn't.
  String get customerLabel {
    final name = customerName;
    if (name != null && name.isNotEmpty) return name;
    final id = customerId;
    if (id != null && id.isNotEmpty) return 'Customer #$id';
    return 'No customer';
  }

  /// Pre-tax value of every line, before discounts or charges.
  double get itemsSubtotal =>
      subtotal ?? items.fold<double>(0, (sum, item) => sum + item.amount);

  /// Sum of every line's own tax.
  double get itemsTaxTotal =>
      taxAmount ?? items.fold<double>(0, (sum, item) => sum + item.tax);

  /// Every discount and redeemed coupon, line- and order-level combined.
  double get discountTotal =>
      discounts.fold<double>(0, (sum, discount) => sum + discount.amount);

  /// Charge amounts, excluding the tax charged on them.
  double get chargesTotal =>
      charges.fold<double>(0, (sum, charge) => sum + charge.amount);

  /// Tax on the charges themselves.
  double get chargesTaxTotal =>
      charges.fold<double>(0, (sum, charge) => sum + charge.taxAmount);

  /// Return server totalAmount if present, else fallback to (itemsSubtotal - discountTotal + chargesTotal).
  double get computedTotal =>
      totalAmount ?? (itemsSubtotal - discountTotal + chargesTotal);

  Customer? get customer {
    final id = customerId;
    if (id == null) return null;
    return Customer(
      id: id,
      name: customerName ?? 'Customer',
      phone: customerPhone,
      email: customerEmail,
    );
  }

  /// Phone and email, whichever the server actually sent.
  String get customerContact =>
      [customerPhone, customerEmail].whereType<String>().join(' · ');

  /// True when only an id came back, so the screen needs a lookup to show a name.
  bool get needsCustomerLookup =>
      (customerId ?? '').isNotEmpty && (customerName ?? '').isEmpty;

  /// True when only an id came back for the store this sale belongs to.
  bool get needsWarehouseLookup =>
      (warehouseId ?? '').isNotEmpty && (warehouseName ?? '').isEmpty;

  /// True when any line item still needs its own name resolved.
  bool get needsItemProductLookup => items.any((item) => item.needsProductLookup);

  /// A copy carrying the details from a separate customer fetch.
  Sale withCustomer(Customer customer) => copyWith(
        customerId: customer.id,
        customerName: customer.name,
        customerPhone: customer.phone,
        customerEmail: customer.email,
      );

  /// A copy carrying the name from a separate warehouse fetch.
  Sale withWarehouseName(String name) => copyWith(warehouseName: name);

  /// A copy carrying resolved item names from a separate product lookup.
  Sale withItems(List<SaleItem> items) => copyWith(items: items);

  Sale copyWith({
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    String? warehouseName,
    List<SaleItem>? items,
  }) =>
      Sale(
        id: id,
        status: status,
        number: number,
        channel: channel,
        saleDate: saleDate,
        customerId: customerId ?? this.customerId,
        customerName: customerName ?? this.customerName,
        customerPhone: customerPhone ?? this.customerPhone,
        customerEmail: customerEmail ?? this.customerEmail,
        warehouseId: warehouseId,
        warehouseName: warehouseName ?? this.warehouseName,
        items: items ?? this.items,
        discounts: discounts,
        charges: charges,
        // Previously dropped here (defaulted to null on every copyWith call,
        // silently discarding the server's real totals in favor of
        // computedTotal's client-side fallback) — carried through now.
        subtotal: subtotal,
        taxAmount: taxAmount,
        totalAmount: totalAmount,
        assignedDeliveryUserId: assignedDeliveryUserId,
        assignedDeliveryUserName: assignedDeliveryUserName,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Sort key for "newest first" — falls back through the fields the server may
  /// or may not send, and sorts unknown dates last rather than first.
  DateTime get sortedAt =>
      parseDate(createdAt) ??
      parseDate(saleDate) ??
      DateTime.fromMillisecondsSinceEpoch(0);
}

class SaleReturnItem {
  const SaleReturnItem({
    required this.productName,
    required this.quantity,
    this.saleItemId,
    this.productId,
    this.refundAmount,
  });

  final String productName;
  final double quantity;
  final String? saleItemId;
  final String? productId;

  /// Discount-aware, computed server-side. Never recomputed locally.
  final double? refundAmount;

  factory SaleReturnItem.fromJson(Map<String, dynamic> json) {
    final product = asMap(json['product']);
    final saleItem = asMap(json['saleItem']);
    return SaleReturnItem(
      productName: firstString(json, ['productName', 'name']) ??
          asString(product?['name']) ??
          asString(asMap(saleItem?['product'])?['name']) ??
          'Item',
      quantity: asDouble(firstOf(json, ['quantity', 'qty'])),
      saleItemId: firstString(json, ['saleItemId']),
      productId: firstString(json, ['productId']) ?? asString(product?['id']),
      refundAmount: asDoubleOrNull(
        firstOf(json, ['refundAmount', 'amount', 'lineTotal', 'total']),
      ),
    );
  }

  /// True when the server sent only a `productId` and this line is still
  /// carrying the generic fallback name.
  bool get needsProductLookup =>
      (productId ?? '').isNotEmpty && productName == 'Item';

  /// A copy carrying the name from a separate product lookup.
  SaleReturnItem withProductName(String name) => SaleReturnItem(
        productName: name,
        quantity: quantity,
        saleItemId: saleItemId,
        productId: productId,
        refundAmount: refundAmount,
      );
}

class SaleReturn {
  const SaleReturn({
    required this.id,
    this.number,
    this.saleId,
    this.saleNumber,
    this.reason,
    this.status,
    this.totalRefundAmount,
    this.items = const [],
    this.createdAt,
  });

  final String id;
  final String? number;
  final String? saleId;
  final String? saleNumber;
  final String? reason;
  final String? status;
  final double? totalRefundAmount;
  final List<SaleReturnItem> items;
  final String? createdAt;

  factory SaleReturn.fromJson(Map<String, dynamic> json) {
    final sale = asMap(json['sale']);
    return SaleReturn(
      id: firstString(json, ['id']) ?? '',
      number: firstString(json, ['returnNumber', 'number', 'code']),
      saleId: firstString(json, ['saleId']) ?? asString(sale?['id']),
      saleNumber: firstString(json, ['saleNumber']) ??
          asString(firstOf(sale ?? {}, ['saleNumber', 'number'])),
      reason: asString(json['reason']),
      status: asString(json['status']),
      totalRefundAmount: asDoubleOrNull(
        firstOf(json, ['totalRefundAmount', 'refundAmount', 'totalAmount', 'total']),
      ),
      items: asMapList(json['items'] ?? json['returnItems'])
          .map(SaleReturnItem.fromJson)
          .toList(),
      createdAt: firstString(json, ['createdAt', 'created_at']),
    );
  }

  String get label => number != null ? 'Return $number' : 'Return #$id';

  double get computedRefund =>
      totalRefundAmount ??
      items.fold<double>(0, (sum, item) => sum + (item.refundAmount ?? 0));

  bool get needsItemProductLookup => items.any((item) => item.needsProductLookup);

  /// A copy carrying resolved item names from a separate product lookup.
  SaleReturn withItems(List<SaleReturnItem> items) => SaleReturn(
        id: id,
        number: number,
        saleId: saleId,
        saleNumber: saleNumber,
        reason: reason,
        status: status,
        totalRefundAmount: totalRefundAmount,
        items: items,
        createdAt: createdAt,
      );
}

/// Which way money moves after an exchange is settled.
enum DifferenceDirection { customerOwes, refundDue, even }

/// `GET /sale-exchanges/:id` nests two full sub-objects rather than flat
/// item lists: the return leg ([saleReturn], the exact same shape
/// `/sale-returns/:id` gives) and the replacement leg ([newSale], the exact
/// same shape `/sales/:id` gives — items, per-item tax breakdown,
/// discounts, charges, all of it). There is no top-level `status`,
/// `paymentMethod`, or `reason` on the exchange itself, and no expanded
/// `payment` relation — the endpoint reports only the settlement
/// [differenceAmount]/[differenceDirectionRaw]; the created Payment row's
/// own id/method aren't part of this response at all.
class SaleExchange {
  const SaleExchange({
    required this.id,
    required this.saleReturn,
    required this.newSale,
    this.differenceAmount,
    this.differenceDirectionRaw,
    this.createdAt,
  });

  final String id;

  /// The return leg — items handed back and their server-computed refund.
  final SaleReturn saleReturn;

  /// The replacement leg, as a full [Sale] — its items, tax, discounts and
  /// charges are exactly what a regular sale detail screen would show.
  final Sale newSale;

  final double? differenceAmount;
  final String? differenceDirectionRaw;
  final String? createdAt;

  factory SaleExchange.fromJson(Map<String, dynamic> json) => SaleExchange(
        id: firstString(json, ['id']) ?? '',
        saleReturn: SaleReturn.fromJson(asMap(json['saleReturn']) ?? const {}),
        newSale: Sale.fromJson(asMap(json['newSale']) ?? const {}),
        differenceAmount: asDoubleOrNull(
          firstOf(json, ['differenceAmount', 'difference', 'balanceAmount']),
        ),
        differenceDirectionRaw:
            firstString(json, ['differenceDirection', 'direction']),
        createdAt: firstString(json, ['createdAt', 'created_at']),
      );

  String get label => 'Exchange #$id';

  /// Items handed back — an alias for `saleReturn.items`.
  List<SaleReturnItem> get returnItems => saleReturn.items;

  /// The replacement items sold — an alias for `newSale.items`.
  List<SaleItem> get newItems => newSale.items;

  /// The original sale being exchanged against — an alias for
  /// `saleReturn.saleId`.
  String? get saleId => saleReturn.saleId;

  /// Why the exchange was made — this lives on the return leg, not the
  /// exchange itself.
  String? get reason => saleReturn.reason;

  DifferenceDirection get direction {
    switch ((differenceDirectionRaw ?? '').toUpperCase()) {
      case 'CUSTOMER_OWES':
        return DifferenceDirection.customerOwes;
      case 'REFUND_DUE':
        return DifferenceDirection.refundDue;
      case 'EVEN':
        return DifferenceDirection.even;
      default:
        final amount = differenceAmount ?? 0;
        if (amount > 0) return DifferenceDirection.customerOwes;
        if (amount < 0) return DifferenceDirection.refundDue;
        return DifferenceDirection.even;
    }
  }

  bool get needsItemProductLookup =>
      returnItems.any((item) => item.needsProductLookup) ||
      newItems.any((item) => item.needsProductLookup);

  /// A copy carrying resolved item names from a separate product lookup.
  SaleExchange withItems({
    List<SaleReturnItem>? returnItems,
    List<SaleItem>? newItems,
  }) =>
      SaleExchange(
        id: id,
        saleReturn:
            returnItems == null ? saleReturn : saleReturn.withItems(returnItems),
        newSale: newItems == null ? newSale : newSale.withItems(newItems),
        differenceAmount: differenceAmount,
        differenceDirectionRaw: differenceDirectionRaw,
        createdAt: createdAt,
      );

  /// A copy carrying the replacement sale's resolved customer.
  SaleExchange withCustomer(Customer customer) => SaleExchange(
        id: id,
        saleReturn: saleReturn,
        newSale: newSale.withCustomer(customer),
        differenceAmount: differenceAmount,
        differenceDirectionRaw: differenceDirectionRaw,
        createdAt: createdAt,
      );

  /// A copy carrying the replacement sale's resolved warehouse name.
  SaleExchange withWarehouseName(String name) => SaleExchange(
        id: id,
        saleReturn: saleReturn,
        newSale: newSale.withWarehouseName(name),
        differenceAmount: differenceAmount,
        differenceDirectionRaw: differenceDirectionRaw,
        createdAt: createdAt,
      );
}
