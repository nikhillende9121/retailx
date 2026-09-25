import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/json.dart';
import '../api_client.dart';
import '../models/paged.dart';
import '../models/purchase.dart';
import 'sales_repository.dart' show LineInput;

/// One line of a goods receipt.
class ReceiveLineInput {
  const ReceiveLineInput({required this.purchaseItemId, required this.quantity});

  final String purchaseItemId;
  final double quantity;

  Map<String, dynamic> toJson() => {
        'purchaseItemId': purchaseItemId,
        'quantity': qtyForApi(quantity),
      };
}

class PurchaseReturnLineInput {
  const PurchaseReturnLineInput({
    required this.purchaseItemId,
    required this.quantity,
  });

  final String purchaseItemId;
  final double quantity;

  Map<String, dynamic> toJson() => {
        'purchaseItemId': purchaseItemId,
        'quantity': qtyForApi(quantity),
      };
}

class PurchasesRepository {
  PurchasesRepository(this._api);

  final ApiClient _api;

  Future<PagedList<Purchase>> list({
    int page = 1,
    String? search,
    String? status,
  }) async {
    final data = await _api.get('purchases', query: {
      'page': page,
      'pageSize': kPageSize,
      'search': search,
      'status': status,
    });
    return PagedList.from(data, Purchase.fromJson);
  }

  Future<Purchase> get(String id) async {
    final data = await _api.get('purchases/$id');
    return Purchase.fromJson(asMap(data) ?? const {});
  }

  Future<Purchase> create({
    required String warehouseId,
    required String supplierId,
    required List<LineInput> items,
    DateTime? purchaseDate,
    DateTime? expectedDate,
    String? notes,
  }) async {
    final body = <String, dynamic>{
      'warehouseId': warehouseId,
      'supplierId': supplierId,
      'purchaseDate': apiDate(purchaseDate ?? DateTime.now()),
      'items': items.map((item) => item.toJson()).toList(),
    };
    if (expectedDate != null) body['expectedDate'] = apiDate(expectedDate);
    if (notes != null && notes.trim().isNotEmpty) body['notes'] = notes.trim();
    final data = await _api.post('purchases', body: body);
    return Purchase.fromJson(asMap(data) ?? const {});
  }

  Future<Purchase> action(String id, String action, {Object? body}) async {
    final data = await _api.post('purchases/$id/$action', body: body);
    final map = asMap(data);
    if (map == null || map.isEmpty) return get(id);
    return Purchase.fromJson(map);
  }

  Future<Purchase> confirm(String id) => action(id, 'confirm');

  Future<Purchase> cancel(String id) => action(id, 'cancel');

  /// Receiving can be partial (`ORDERED -> PARTIALLY_RECEIVED`). Sending no
  /// lines is treated by the server as "receive everything outstanding".
  Future<Purchase> receive(String id, {List<ReceiveLineInput>? items}) {
    final body = (items == null || items.isEmpty)
        ? null
        : {'items': items.map((item) => item.toJson()).toList()};
    return action(id, 'receive', body: body);
  }

  // ---------------------------------------------------- purchase returns

  Future<PagedList<PurchaseReturn>> listReturns({
    int page = 1,
    String? search,
  }) async {
    final data = await _api.get('purchase-returns', query: {
      'page': page,
      'pageSize': kPageSize,
      'search': search,
    });
    return PagedList.from(data, PurchaseReturn.fromJson);
  }

  Future<PurchaseReturn> getReturn(String id) async {
    final data = await _api.get('purchase-returns/$id');
    return PurchaseReturn.fromJson(asMap(data) ?? const {});
  }

  /// Scoped against the parent purchase's warehouse, so no warehouseId is sent.
  Future<PurchaseReturn> createReturn({
    required String purchaseId,
    required String reason,
    required List<PurchaseReturnLineInput> items,
  }) async {
    final data = await _api.post('purchase-returns', body: {
      'purchaseId': purchaseId,
      'reason': reason,
      'items': items.map((item) => item.toJson()).toList(),
    });
    return PurchaseReturn.fromJson(asMap(data) ?? const {});
  }
}
