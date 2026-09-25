import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/json.dart';
import '../api_client.dart';
import '../models/inventory.dart';
import '../models/paged.dart';

class TransferLineInput {
  const TransferLineInput({required this.productId, required this.quantity});

  final String productId;
  final double quantity;

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'requestedQuantity': qtyForApi(quantity),
      };
}

/// One line of a `/ship` or `/receive` call — the quantity the caller chose
/// for that line, capped client-side against the previous stage's amount.
class TransferStageInput {
  const TransferStageInput({
    required this.stockTransferItemId,
    required this.quantity,
  });

  final String stockTransferItemId;
  final double quantity;
}

class InventoryRepository {
  InventoryRepository(this._api);

  final ApiClient _api;

  /// Pass the caller's own [warehouseId] when it's known.
  ///
  /// The server forces the filter to the caller's store when the parameter is
  /// omitted, so both work for a scoped account — but sending it explicitly
  /// matches how the endpoint is exercised elsewhere (Postman collection:
  /// `/inventory/balance?warehouseId=…`) and removes any doubt about which
  /// store the rows belong to. It's asserted against scope server-side, and
  /// this app only ever sends its own id.
  Future<PagedList<StockBalance>> balance({
    int page = 1,
    String? search,
    String? productId,
    String? warehouseId,
    int pageSize = 50,
  }) async {
    final data = await _api.get('inventory/balance', query: {
      'page': page,
      'pageSize': pageSize,
      'search': search,
      'productId': productId,
      'warehouseId': warehouseId,
    });
    return PagedList.from(data, StockBalance.fromJson);
  }

  /// Manual stock correction. There is no list endpoint for past adjustments.
  ///
  /// ASSUMPTION: the payload is `{ warehouseId, productId, quantity, reason }`
  /// with a signed quantity (negative to write stock off). The guides document
  /// the route and its permission but not the body; if the backend expects a
  /// separate `type: INCREASE|DECREASE`, add it here — this is the only place
  /// that builds this request.
  Future<void> adjust({
    required String warehouseId,
    required String productId,
    required double quantity,
    required String reason,
  }) async {
    await _api.post('stock-adjustments', body: {
      'warehouseId': warehouseId,
      'productId': productId,
      'quantity': qtyForApi(quantity),
      'reason': reason,
    });
  }

  // --------------------------------------------------------- transfers

  /// Filtered to transfers where this store is on *either* side.
  Future<PagedList<StockTransfer>> transfers({
    int page = 1,
    String? search,
    String? status,
  }) async {
    final data = await _api.get('stock-transfers', query: {
      'page': page,
      'pageSize': kPageSize,
      'search': search,
      'status': status,
    });
    return PagedList.from(data, StockTransfer.fromJson);
  }

  Future<StockTransfer> transfer(String id) async {
    final data = await _api.get('stock-transfers/$id');
    return StockTransfer.fromJson(asMap(data) ?? const {});
  }

  /// `POST /stock-transfers` only ever takes a destination — the source
  /// warehouse isn't chosen until a tenant admin approves the request (see
  /// `Docs/business-rules/stock-transfer.md`), so there's no
  /// `fromWarehouseId` to pass here at all.
  Future<StockTransfer> createTransfer({
    required String toWarehouseId,
    required List<TransferLineInput> items,
    DateTime? transferDate,
  }) async {
    final body = <String, dynamic>{
      'toWarehouseId': toWarehouseId,
      'transferDate': apiDate(transferDate ?? DateTime.now()),
      'items': items.map((item) => item.toJson()).toList(),
    };
    final data = await _api.post('stock-transfers', body: body);
    return StockTransfer.fromJson(asMap(data) ?? const {});
  }

  /// Sets `fromWarehouseId` (a DRAFT transfer has none yet) and the
  /// per-line approved quantity, which caps what `/ship` can move out.
  Future<StockTransfer> approveTransfer(
    String id, {
    required String fromWarehouseId,
    required List<TransferStageInput> items,
  }) async {
    final body = <String, dynamic>{
      'fromWarehouseId': fromWarehouseId,
      'items': [
        for (final item in items)
          {
            'stockTransferItemId': item.stockTransferItemId,
            'approvedQuantity': qtyForApi(item.quantity),
          },
      ],
    };
    final data = await _api.post('stock-transfers/$id/approve', body: body);
    final map = asMap(data);
    if (map == null || map.isEmpty) return transfer(id);
    return StockTransfer.fromJson(map);
  }

  Future<StockTransfer> shipTransfer(
    String id,
    List<TransferStageInput> items,
  ) =>
      _stageAction(id, 'ship', items, quantityKey: 'shippedQuantity');

  Future<StockTransfer> receiveTransfer(
    String id,
    List<TransferStageInput> items,
  ) =>
      _stageAction(id, 'receive', items, quantityKey: 'receivedQuantity');

  Future<StockTransfer> _stageAction(
    String id,
    String action,
    List<TransferStageInput> items, {
    required String quantityKey,
  }) async {
    final body = <String, dynamic>{
      'items': [
        for (final item in items)
          {
            'stockTransferItemId': item.stockTransferItemId,
            quantityKey: qtyForApi(item.quantity),
          },
      ],
    };
    final data = await _api.post('stock-transfers/$id/$action', body: body);
    final map = asMap(data);
    if (map == null || map.isEmpty) return transfer(id);
    return StockTransfer.fromJson(map);
  }

  Future<StockTransfer> cancelTransfer(String id) async {
    final data = await _api.post('stock-transfers/$id/cancel');
    final map = asMap(data);
    if (map == null || map.isEmpty) return transfer(id);
    return StockTransfer.fromJson(map);
  }
}
