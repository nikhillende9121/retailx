import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/json.dart';
import '../api_client.dart';
import '../models/paged.dart';
import '../models/sale.dart';

/// A single line being sent to the server.
class LineInput {
  const LineInput({
    required this.productId,
    required this.quantity,
    required this.price,
    this.discount = 0,
  });

  final String productId;
  final double quantity;
  final double price;

  /// Money off this line, in rupees. Omitted from the payload when zero, so a
  /// sale without discounts sends exactly the body it always did.
  final double discount;

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'productId': productId,
      'quantity': qtyForApi(quantity),
      'price': moneyForApi(price),
    };
    if (discount > 0) json['discountAmount'] = moneyForApi(discount);
    return json;
  }
}

/// A line being sent back — references the original sale line, not the product.
class ReturnLineInput {
  const ReturnLineInput({required this.saleItemId, required this.quantity});

  final String saleItemId;
  final double quantity;

  Map<String, dynamic> toJson() => {
        'saleItemId': saleItemId,
        'quantity': qtyForApi(quantity),
      };
}

/// An extra charge being sent to the server (shipping, handling, packaging).
class ChargeInput {
  const ChargeInput({required this.name, required this.amount});

  final String name;
  final double amount;

  Map<String, dynamic> toJson() => {
        'name': name,
        'amount': moneyForApi(amount),
      };
}

class SalesRepository {
  SalesRepository(this._api);

  final ApiClient _api;

  // ---------------------------------------------------------------- sales

  /// Always filtered to the caller's own warehouse server-side; no warehouse
  /// parameter is sent because there is nothing else this account could ask for.
  /// Newest first is requested via `sortBy`/`sortOrder`.
  ///
  /// ASSUMPTION: those parameter names aren't in the guides. Unknown query
  /// params are stripped by the server's validation rather than rejected, so
  /// this is safe either way — and the list screens sort client-side too, so the
  /// order is correct whether or not the server honours it.
  Future<PagedList<Sale>> list({
    int page = 1,
    String? search,
    String? status,
    String sortBy = 'createdAt',
    String sortOrder = 'desc',
  }) async {
    final data = await _api.get('sales', query: {
      'page': page,
      'pageSize': kPageSize,
      'search': search,
      'status': status,
      'sortBy': sortBy,
      'sortOrder': sortOrder,
    });
    return PagedList.from(data, Sale.fromJson);
  }

  Future<Sale> get(String id) async {
    final data = await _api.get('sales/$id');
    return Sale.fromJson(asMap(data) ?? const {});
  }

  /// ASSUMED DISCOUNT CONTRACT — the one place manual discounts are built.
  ///
  /// The guides document only `couponCode` (server-decided), so these field
  /// names are the app's proposal for the manual case:
  ///
  ///   sale level : `discountAmount` (rupees) *or* `discountPercent`
  ///   line level : `discountAmount` on each entry of `items`
  ///
  /// Both are omitted entirely unless a discount was actually entered, so until
  /// the backend adds them nothing changes for an ordinary sale. If the API ends
  /// up naming them differently, this method and [LineInput.toJson] are the only
  /// things to edit.
  Future<Sale> create({
    required String warehouseId,
    required List<LineInput> items,
    String? customerId,
    DateTime? saleDate,
    String channel = kPosChannel,
    String? couponCode,
    double discountAmount = 0,
    double? discountPercent,
    List<ChargeInput>? charges,
    // Optional — only `CREDIT` does anything today (charges the sale to the
    // customer's credit ledger, enforced against their limit; see
    // credit_androidChanges.md). Every other value/omission is currently a
    // no-op server-side, same as not sending it at all. Requires
    // [customerId] and the CREDIT_PAYMENT feature — the server 400s
    // VALIDATION_ERROR or 403s FEATURE_NOT_ENABLED otherwise, and can 422
    // CREDIT_LIMIT_EXCEEDED if this sale would push the customer over their
    // limit (see AppError.isCreditLimitExceeded).
    String? paymentMethod,
  }) async {
    final body = <String, dynamic>{
      'warehouseId': warehouseId,
      'channel': channel,
      'saleDate': apiDate(saleDate ?? DateTime.now()),
      'items': items.map((item) => item.toJson()).toList(),
    };
    if (customerId != null && customerId.isNotEmpty) {
      body['customerId'] = customerId;
    }
    if (couponCode != null && couponCode.trim().isNotEmpty) {
      body['couponCode'] = couponCode.trim();
    }
    if (discountPercent != null && discountPercent > 0) {
      body['discountPercent'] = qtyForApi(discountPercent);
    } else if (discountAmount > 0) {
      body['discountAmount'] = moneyForApi(discountAmount);
    }
    if (charges != null && charges.isNotEmpty) {
      body['charges'] = charges.map((c) => c.toJson()).toList();
    }
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      body['paymentMethod'] = paymentMethod;
    }
    final data = await _api.post('sales', body: body);
    return Sale.fromJson(asMap(data) ?? const {});
  }

  /// Lifecycle transitions are distinct endpoints, not a generic "advance".
  Future<Sale> action(String id, String action) async {
    final data = await _api.post('sales/$id/$action');
    final map = asMap(data);
    // Some action handlers return the updated document, others just a message.
    if (map == null || map.isEmpty) return get(id);
    return Sale.fromJson(map);
  }

  Future<Sale> confirm(String id) => action(id, 'confirm');

  Future<Sale> complete(String id) => action(id, 'complete');

  /// Who a sale can be assigned to for delivery — call before showing the
  /// assignee picker in the Ship flow. Gated server-side by `SALE.SHIP` (not
  /// `USER.VIEW`): whoever can ship a sale can see who it could go to.
  Future<List<DeliveryAssignee>> deliveryAssignees() async {
    final data = await _api.get('sales/delivery-assignees');
    return asMapList(data).map(DeliveryAssignee.fromJson).toList();
  }

  /// Ship requires an assignee now — unlike every other lifecycle action,
  /// which is just `action(id, name)` with no body. The server 400s
  /// (`VALIDATION_ERROR`) if [assignedDeliveryUserId] isn't in this tenant
  /// or doesn't hold `SALE.DELIVER`.
  Future<Sale> ship(String id, {required String assignedDeliveryUserId}) async {
    final data = await _api.post(
      'sales/$id/ship',
      body: {'assignedDeliveryUserId': assignedDeliveryUserId},
    );
    final map = asMap(data);
    if (map == null || map.isEmpty) return get(id);
    return Sale.fromJson(map);
  }

  // -------------------------------------------------------- sale returns

  Future<PagedList<SaleReturn>> listReturns({int page = 1, String? search}) async {
    final data = await _api.get('sale-returns', query: {
      'page': page,
      'pageSize': kPageSize,
      'search': search,
    });
    return PagedList.from(data, SaleReturn.fromJson);
  }

  Future<SaleReturn> getReturn(String id) async {
    final data = await _api.get('sale-returns/$id');
    return SaleReturn.fromJson(asMap(data) ?? const {});
  }

  /// The response carries a discount-aware `refundAmount` per line and a
  /// `totalRefundAmount` — displayed as-is, never recomputed on device.
  Future<SaleReturn> createReturn({
    required String saleId,
    required String reason,
    required List<ReturnLineInput> items,
  }) async {
    final data = await _api.post('sale-returns', body: {
      'saleId': saleId,
      'reason': reason,
      'items': items.map((item) => item.toJson()).toList(),
    });
    return SaleReturn.fromJson(asMap(data) ?? const {});
  }

  // ------------------------------------------------------ sale exchanges

  Future<PagedList<SaleExchange>> listExchanges({
    int page = 1,
    String? search,
  }) async {
    final data = await _api.get('sale-exchanges', query: {
      'page': page,
      'pageSize': kPageSize,
      'search': search,
    });
    return PagedList.from(data, SaleExchange.fromJson);
  }

  Future<SaleExchange> getExchange(String id) async {
    final data = await _api.get('sale-exchanges/$id');
    return SaleExchange.fromJson(asMap(data) ?? const {});
  }

  /// Return some lines and sell replacements in one transaction; the response's
  /// `differenceAmount` + `differenceDirection` say how to settle.
  Future<SaleExchange> createExchange({
    required String saleId,
    required String reason,
    required List<ReturnLineInput> returnItems,
    required List<LineInput> newItems,
    required String paymentMethod,
  }) async {
    final data = await _api.post('sale-exchanges', body: {
      'saleId': saleId,
      'reason': reason,
      'returnItems': returnItems.map((item) => item.toJson()).toList(),
      'newItems': newItems.map((item) => item.toJson()).toList(),
      'paymentMethod': paymentMethod,
    });
    return SaleExchange.fromJson(asMap(data) ?? const {});
  }
}
