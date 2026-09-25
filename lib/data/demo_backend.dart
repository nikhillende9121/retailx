import '../core/errors.dart';

/// An in-memory stand-in for the REST API, for walking through the app without
/// a backend.
///
/// It is wired in at exactly one point — the top of [ApiClient.send] — and
/// returns the same *unwrapped* `data` payloads the real envelope would, so
/// every screen, repository, model and error path below it is the real code.
/// Nothing here runs unless [enabled] is set true by the demo button on the
/// login screen.
///
/// State is mutable and lives for the life of the process: confirm a sale and
/// stock really drops, receive a purchase and it really goes up.
class DemoBackend {
  DemoBackend._();

  static final DemoBackend instance = DemoBackend._();

  /// Flipped on by "Explore in demo mode". Never true in a normal session.
  static bool enabled = false;

  static const String warehouseId = '5';
  static const String warehouseName = 'Downtown Store';

  int _seq = 1000;
  String _nextId() => '${_seq++}';

  bool _seeded = false;

  final List<Map<String, dynamic>> _products = [
    {'id': 'p1', 'name': 'Espresso Beans 1kg', 'sku': 'ESP-1000', 'unit': 'bag', 'sellingPrice': 899},
    {'id': 'p2', 'name': 'Ceramic Mug', 'sku': 'MUG-220', 'unit': 'pc', 'sellingPrice': 349},
    {'id': 'p3', 'name': 'Pour-over Filter Papers', 'sku': 'FLT-100', 'unit': 'box', 'sellingPrice': 199},
    {'id': 'p4', 'name': 'Cold Brew Bottle 500ml', 'sku': 'CB-500', 'unit': 'pc', 'sellingPrice': 259},
    {'id': 'p5', 'name': 'Milk Frother', 'sku': 'FRT-01', 'unit': 'pc', 'sellingPrice': 1499},
    {'id': 'p6', 'name': 'Decaf Blend 500g', 'sku': 'DEC-500', 'unit': 'bag', 'sellingPrice': 649},
    {'id': 'p7', 'name': 'Travel Tumbler', 'sku': 'TMB-350', 'unit': 'pc', 'sellingPrice': 1099},
    {'id': 'p8', 'name': 'Chocolate Biscotti', 'sku': 'BSC-12', 'unit': 'pack', 'sellingPrice': 149},
    {'id': 'p9', 'name': 'Green Tea Sachets', 'sku': 'GT-25', 'unit': 'box', 'sellingPrice': 299},
    {'id': 'p10', 'name': 'Reusable Steel Straw', 'sku': 'STR-04', 'unit': 'set', 'sellingPrice': 199},
    {'id': 'p11', 'name': 'Barista Apron', 'sku': 'APR-01', 'unit': 'pc', 'sellingPrice': 799},
    {'id': 'p12', 'name': 'Syrup — Vanilla 750ml', 'sku': 'SYR-VAN', 'unit': 'bottle', 'sellingPrice': 459},
    {'id': 'p13', 'name': 'Syrup — Hazelnut 750ml', 'sku': 'SYR-HAZ', 'unit': 'bottle', 'sellingPrice': 459},
    {'id': 'p14', 'name': 'Gift Card Sleeve', 'sku': 'GCS-10', 'unit': 'pc', 'sellingPrice': 49},
  ];

  final Map<String, double> _stock = {
    'p1': 24, 'p2': 40, 'p3': 12, 'p4': 30, 'p5': 4, 'p6': 9, 'p7': 7,
    'p8': 55, 'p9': 18, 'p10': 0, 'p11': 6, 'p12': 11, 'p13': 3, 'p14': 80,
  };

  final List<Map<String, dynamic>> _customers = [
    {'id': 'c1', 'name': 'Aarti Deshpande', 'phone': '+91 98200 11223'},
    {'id': 'c2', 'name': 'Rohit Kulkarni', 'phone': '+91 99870 55412'},
    {'id': 'c3', 'name': 'Meera Nair', 'phone': '+91 90045 78123', 'email': 'meera@example.com'},
    {'id': 'c4', 'name': 'Sandeep Rao', 'phone': '+91 91234 00988'},
    {'id': 'c5', 'name': 'Priya Shah', 'phone': '+91 98765 43210'},
  ];

  final List<Map<String, dynamic>> _suppliers = [
    {'id': 's1', 'name': 'Blue Tokai Wholesale', 'phone': '+91 22 4001 2233'},
    {'id': 's2', 'name': 'Kitchenware Depot', 'phone': '+91 22 4990 8877'},
    {'id': 's3', 'name': 'Sweet Supply Co.', 'phone': '+91 22 3311 5566'},
  ];

  final List<Map<String, dynamic>> _deliveryAssignees = [
    {'id': 'u1', 'name': 'Courier One'},
    {'id': 'u2', 'name': 'Courier Two'},
  ];

  final List<Map<String, dynamic>> _sales = [];
  final List<Map<String, dynamic>> _saleReturns = [];
  final List<Map<String, dynamic>> _saleExchanges = [];
  final List<Map<String, dynamic>> _purchases = [];
  final List<Map<String, dynamic>> _purchaseReturns = [];
  final List<Map<String, dynamic>> _transfers = [];

  // ------------------------------------------------------------------ routing

  Future<dynamic> handle(
    String method,
    String path,
    Map<String, dynamic>? query,
    Object? body,
  ) async {
    _seed();
    // A touch of latency so loading states are actually visible.
    await Future<void>.delayed(const Duration(milliseconds: 220));

    final data = body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
    final search = (query?['search'] ?? '').toString().toLowerCase();
    final status = (query?['status'] ?? '').toString();
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    final key = '$method ${segments.join('/')}';

    switch (key) {
      case 'POST auth/login':
        return {'accessToken': 'demo-access-token', 'refreshToken': 'demo-refresh-token'};
      case 'POST auth/refresh':
        return {'accessToken': 'demo-access-token', 'refreshToken': 'demo-refresh-token'};
      case 'GET auth/me':
        return _me();
      case 'GET warehouses':
        return _page([_warehouse()]);
      case 'GET products':
        return _page(_products
            .where((p) => _matches(search, [p['name'], p['sku']]))
            .toList());
      case 'GET customers':
        return _page(_customers
            .where((c) => _matches(search, [c['name'], c['phone'], c['email']]))
            .toList());
      case 'GET suppliers':
        return _page(_suppliers
            .where((s) => _matches(search, [s['name']]))
            .toList());
      case 'GET inventory/balance':
        return _page(_balances(search));
      case 'POST stock-adjustments':
        return _adjust(data);
      case 'GET sales':
        return _page(_filtered(_sales, search, status, ['saleNumber', 'customerName']));
      case 'POST sales':
        return _createSale(data);
      case 'GET sales/delivery-assignees':
        return _deliveryAssignees;
      case 'GET sale-returns':
        return _page(_saleReturns);
      case 'POST sale-returns':
        return _createSaleReturn(data);
      case 'GET sale-exchanges':
        return _page(_saleExchanges);
      case 'POST sale-exchanges':
        return _createExchange(data);
      case 'GET purchases':
        return _page(_filtered(_purchases, search, status, ['purchaseNumber', 'supplierName']));
      case 'POST purchases':
        return _createPurchase(data);
      case 'GET purchase-returns':
        return _page(_purchaseReturns);
      case 'POST purchase-returns':
        return _createPurchaseReturn(data);
      case 'GET stock-transfers':
        return _page(_filtered(_transfers, search, status, ['transferNumber']));
      case 'POST stock-transfers':
        return _createTransfer(data);
    }

    // Two- and three-segment routes: /sales/{id}, /sales/{id}/{action}, ...
    if (segments.length >= 2) {
      final collection = segments[0];
      final id = segments[1];
      final action = segments.length >= 3 ? segments[2] : null;

      switch (collection) {
        case 'warehouses':
          return _warehouse();
        case 'sales':
          final sale = _find(_sales, id);
          if (action == null) return sale;
          return _saleAction(sale, action, data);
        case 'sale-returns':
          return _find(_saleReturns, id);
        case 'sale-exchanges':
          return _find(_saleExchanges, id);
        case 'purchases':
          final purchase = _find(_purchases, id);
          if (action == null) return purchase;
          return _purchaseAction(purchase, action, data);
        case 'purchase-returns':
          return _find(_purchaseReturns, id);
        case 'stock-transfers':
          final transfer = _find(_transfers, id);
          if (action == null) return transfer;
          return _transferAction(transfer, action);
      }
    }

    throw AppError(
      code: ErrorCodes.notFound,
      message: 'Demo mode has no route for $method /$path.',
      status: 404,
    );
  }

  // -------------------------------------------------------------- primitives

  Map<String, dynamic> _me() => {
        'id': '4',
        'name': 'Demo Cashier',
        'email': 'demo@store.test',
        'tenantId': '2',
        'warehouseId': warehouseId,
        'warehouseName': warehouseName,
        'role': {'id': '3', 'name': 'Store Manager (demo)'},
        'permissions': [
          'SALE.VIEW', 'SALE.CREATE', 'SALE.CONFIRM', 'SALE.UPDATE', 'SALE.EXCHANGE',
          'SALE_RETURN.VIEW', 'SALE_RETURN.CREATE',
          'PURCHASE.VIEW', 'PURCHASE.CREATE', 'PURCHASE.UPDATE', 'PURCHASE.RECEIVE',
          'PURCHASE_RETURN.VIEW', 'PURCHASE_RETURN.CREATE',
          'INVENTORY.VIEW', 'INVENTORY.ADJUST',
          'STOCK_TRANSFER.VIEW', 'STOCK_TRANSFER.CREATE', 'STOCK_TRANSFER.SHIP',
          'STOCK_TRANSFER.RECEIVE', 'STOCK_TRANSFER.UPDATE',
          'WAREHOUSE.VIEW',
        ],
        'enabledFeatures': [
          'SALES', 'SALE_RETURN', 'SALE_EXCHANGE', 'PURCHASE', 'PURCHASE_RETURN',
          'INVENTORY', 'STOCK_TRANSFER',
        ],
      };

  Map<String, dynamic> _warehouse() => {
        'id': warehouseId,
        'name': warehouseName,
        'code': 'DT-01',
        'address': 'Ground floor, Linking Road',
      };

  Map<String, dynamic> _page(List<Map<String, dynamic>> items) => {
        'items': items,
        'pagination': {
          'page': 1,
          'pageSize': items.length,
          'total': items.length,
          'totalPages': 1,
        },
      };

  bool _matches(String search, List<Object?> fields) {
    if (search.isEmpty) return true;
    return fields.any(
      (f) => (f ?? '').toString().toLowerCase().contains(search),
    );
  }

  List<Map<String, dynamic>> _filtered(
    List<Map<String, dynamic>> source,
    String search,
    String status,
    List<String> searchFields,
  ) {
    return source.where((row) {
      if (status.isNotEmpty && row['status'] != status) return false;
      return _matches(search, searchFields.map((f) => row[f]).toList());
    }).toList();
  }

  Map<String, dynamic> _find(List<Map<String, dynamic>> source, String id) {
    for (final row in source) {
      if (row['id'] == id) return row;
    }
    throw AppError(
      code: ErrorCodes.notFound,
      message: 'Not found in demo data.',
      status: 404,
    );
  }

  Map<String, dynamic> _product(String id) {
    for (final p in _products) {
      if (p['id'] == id) return p;
    }
    return {'id': id, 'name': 'Product $id', 'sku': id};
  }

  List<Map<String, dynamic>> _balances(String search) {
    final rows = <Map<String, dynamic>>[];
    for (final product in _products) {
      final id = product['id'] as String;
      if (!_matches(search, [product['name'], product['sku']])) continue;
      rows.add({
        'productId': id,
        'productName': product['name'],
        'sku': product['sku'],
        'unit': product['unit'],
        'quantity': _stock[id] ?? 0,
        'sellingPrice': product['sellingPrice'],
      });
    }
    return rows;
  }

  double _num(Object? value) =>
      value == null ? 0 : (num.tryParse(value.toString())?.toDouble() ?? 0);

  String _today() => DateTime.now().toIso8601String().split('T').first;

  String _now() => DateTime.now().toIso8601String();

  // ------------------------------------------------------------------- sales

  Map<String, dynamic> _createSale(Map<String, dynamic> data) {
    final lines = <Map<String, dynamic>>[];
    var subtotal = 0.0;

    for (final raw in (data['items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final productId = item['productId'].toString();
      final quantity = _num(item['quantity']);
      final price = _num(item['price']);
      final available = _stock[productId] ?? 0;

      // The one error worth reproducing faithfully — it drives real UI copy.
      if (quantity > available) {
        throw AppError(
          code: ErrorCodes.insufficientStock,
          message: 'Only ${available.toInt()} of '
              '${_product(productId)['name']} left in stock.',
          status: 422,
        );
      }

      subtotal += quantity * price;
      lines.add({
        'id': 'si${_nextId()}',
        'productId': productId,
        'productName': _product(productId)['name'],
        'sku': _product(productId)['sku'],
        'quantity': quantity,
        'price': price,
        'lineTotal': quantity * price,
        'returnedQuantity': 0,
      });
    }

    final discount = (data['couponCode'] ?? '').toString().isEmpty
        ? 0.0
        : (subtotal * 0.1);
    final customerId = data['customerId']?.toString();

    final sale = {
      'id': _nextId(),
      'saleNumber': 'S-${1400 + _sales.length + 1}',
      'status': 'DRAFT',
      'channel': data['channel'] ?? 'POS',
      'saleDate': data['saleDate'] ?? _today(),
      'customerId': customerId,
      'customerName': customerId == null
          ? null
          : _customers.firstWhere(
              (c) => c['id'] == customerId,
              orElse: () => {'name': 'Customer'},
            )['name'],
      'warehouseId': warehouseId,
      'warehouseName': warehouseName,
      'subtotal': subtotal,
      'discountAmount': discount,
      'taxAmount': 0,
      'totalAmount': subtotal - discount,
      'items': lines,
      'createdAt': _now(),
    };

    _sales.insert(0, sale);
    return sale;
  }

  Map<String, dynamic> _saleAction(
    Map<String, dynamic> sale,
    String action, [
    Map<String, dynamic> data = const {},
  ]) {
    const transitions = {
      'confirm': 'CONFIRMED',
      'process': 'PROCESSING',
      'pack': 'PACKED',
      'ship': 'SHIPPED',
      'deliver': 'DELIVERED',
      'complete': 'COMPLETED',
      'cancel': 'CANCELLED',
    };
    final next = transitions[action];
    if (next == null) {
      throw AppError(
        code: ErrorCodes.validation,
        message: 'Unknown action "$action".',
        status: 400,
      );
    }

    if (action == 'ship') {
      final assigneeId = data['assignedDeliveryUserId']?.toString();
      if (assigneeId == null || assigneeId.isEmpty) {
        throw const AppError(
          code: ErrorCodes.validation,
          message: 'assignedDeliveryUserId is required to ship a sale.',
          status: 400,
        );
      }
      final assignee = _deliveryAssignees.firstWhere(
        (a) => a['id'] == assigneeId,
        orElse: () => throw const AppError(
          code: ErrorCodes.validation,
          message: 'assignedDeliveryUserId does not belong to this tenant.',
          status: 400,
        ),
      );
      sale['assignedDeliveryUserId'] = assignee['id'];
      sale['assignedDeliveryUserName'] = assignee['name'];
    }

    // Confirming is what moves stock, same as the real service.
    if (action == 'confirm' && sale['status'] == 'DRAFT') {
      for (final raw in (sale['items'] as List? ?? const [])) {
        final item = Map<String, dynamic>.from(raw as Map);
        final id = item['productId'].toString();
        _stock[id] = (_stock[id] ?? 0) - _num(item['quantity']);
      }
    }
    if (action == 'cancel' &&
        (sale['status'] == 'CONFIRMED' || sale['status'] == 'PROCESSING')) {
      for (final raw in (sale['items'] as List? ?? const [])) {
        final item = Map<String, dynamic>.from(raw as Map);
        final id = item['productId'].toString();
        _stock[id] = (_stock[id] ?? 0) + _num(item['quantity']);
      }
    }

    sale['status'] = next;
    return sale;
  }

  Map<String, dynamic> _createSaleReturn(Map<String, dynamic> data) {
    final sale = _find(_sales, data['saleId'].toString());
    final saleItems = (sale['items'] as List).cast<Map<String, dynamic>>();
    final discountRatio = _num(sale['subtotal']) == 0
        ? 0.0
        : _num(sale['discountAmount']) / _num(sale['subtotal']);

    final lines = <Map<String, dynamic>>[];
    var refund = 0.0;

    for (final raw in (data['items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final saleItemId = item['saleItemId'].toString();
      final quantity = _num(item['quantity']);
      final saleItem = saleItems.firstWhere(
        (si) => si['id'] == saleItemId,
        orElse: () => <String, dynamic>{},
      );
      if (saleItem.isEmpty) continue;

      // Discount-aware, exactly the thing the UI must not recompute itself.
      final lineRefund = quantity * _num(saleItem['price']) * (1 - discountRatio);
      refund += lineRefund;

      saleItem['returnedQuantity'] = _num(saleItem['returnedQuantity']) + quantity;
      final productId = saleItem['productId'].toString();
      _stock[productId] = (_stock[productId] ?? 0) + quantity;

      lines.add({
        'id': 'ri${_nextId()}',
        'saleItemId': saleItemId,
        'productId': productId,
        'productName': saleItem['productName'],
        'quantity': quantity,
        'refundAmount': lineRefund,
      });
    }

    final saleReturn = {
      'id': _nextId(),
      'returnNumber': 'R-${300 + _saleReturns.length + 1}',
      'saleId': sale['id'],
      'saleNumber': sale['saleNumber'],
      'reason': data['reason'],
      'status': 'COMPLETED',
      'totalRefundAmount': refund,
      'items': lines,
      'createdAt': _now(),
    };

    _saleReturns.insert(0, saleReturn);
    return saleReturn;
  }

  Map<String, dynamic> _createExchange(Map<String, dynamic> data) {
    final sale = _find(_sales, data['saleId'].toString());
    final saleItems = (sale['items'] as List).cast<Map<String, dynamic>>();

    final returnLines = <Map<String, dynamic>>[];
    var returnValue = 0.0;
    for (final raw in (data['returnItems'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final saleItemId = item['saleItemId'].toString();
      final quantity = _num(item['quantity']);
      final saleItem = saleItems.firstWhere(
        (si) => si['id'] == saleItemId,
        orElse: () => <String, dynamic>{},
      );
      if (saleItem.isEmpty) continue;
      final value = quantity * _num(saleItem['price']);
      returnValue += value;
      saleItem['returnedQuantity'] = _num(saleItem['returnedQuantity']) + quantity;
      final productId = saleItem['productId'].toString();
      _stock[productId] = (_stock[productId] ?? 0) + quantity;
      returnLines.add({
        'id': 'xi${_nextId()}',
        'saleItemId': saleItemId,
        'productId': productId,
        'productName': saleItem['productName'],
        'quantity': quantity,
        'refundAmount': value,
      });
    }

    final newLines = <Map<String, dynamic>>[];
    var newValue = 0.0;
    for (final raw in (data['newItems'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final productId = item['productId'].toString();
      final quantity = _num(item['quantity']);
      final price = _num(item['price']);
      newValue += quantity * price;
      _stock[productId] = (_stock[productId] ?? 0) - quantity;
      newLines.add({
        'id': 'xn${_nextId()}',
        'productId': productId,
        'productName': _product(productId)['name'],
        'quantity': quantity,
        'price': price,
        'lineTotal': quantity * price,
      });
    }

    final difference = newValue - returnValue;
    final exchange = {
      'id': _nextId(),
      'exchangeNumber': 'X-${120 + _saleExchanges.length + 1}',
      'saleId': sale['id'],
      'reason': data['reason'],
      'status': 'COMPLETED',
      'differenceAmount': difference.abs(),
      'differenceDirection': difference > 0
          ? 'CUSTOMER_OWES'
          : difference < 0
              ? 'REFUND_DUE'
              : 'EVEN',
      'paymentMethod': data['paymentMethod'],
      'returnItems': returnLines,
      'newItems': newLines,
      'createdAt': _now(),
    };

    _saleExchanges.insert(0, exchange);
    return exchange;
  }

  // --------------------------------------------------------------- purchases

  Map<String, dynamic> _createPurchase(Map<String, dynamic> data) {
    final lines = <Map<String, dynamic>>[];
    var total = 0.0;
    for (final raw in (data['items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final productId = item['productId'].toString();
      final quantity = _num(item['quantity']);
      final price = _num(item['price']);
      total += quantity * price;
      lines.add({
        'id': 'pi${_nextId()}',
        'productId': productId,
        'productName': _product(productId)['name'],
        'sku': _product(productId)['sku'],
        'quantity': quantity,
        'price': price,
        'receivedQuantity': 0,
        'lineTotal': quantity * price,
      });
    }

    final supplierId = data['supplierId']?.toString();
    final purchase = {
      'id': _nextId(),
      'purchaseNumber': 'PO-${700 + _purchases.length + 1}',
      'status': 'DRAFT',
      'supplierId': supplierId,
      'supplierName': _suppliers.firstWhere(
        (s) => s['id'] == supplierId,
        orElse: () => {'name': 'Supplier'},
      )['name'],
      'warehouseId': warehouseId,
      'purchaseDate': data['purchaseDate'] ?? _today(),
      'expectedDate': data['expectedDate'],
      'totalAmount': total,
      'notes': data['notes'],
      'items': lines,
      'createdAt': _now(),
    };

    _purchases.insert(0, purchase);
    return purchase;
  }

  Map<String, dynamic> _purchaseAction(
    Map<String, dynamic> purchase,
    String action,
    Map<String, dynamic> data,
  ) {
    switch (action) {
      case 'confirm':
        purchase['status'] = 'ORDERED';
        return purchase;
      case 'cancel':
        purchase['status'] = 'CANCELLED';
        return purchase;
      case 'receive':
        final items = (purchase['items'] as List).cast<Map<String, dynamic>>();
        final requested = <String, double>{};
        for (final raw in (data['items'] as List? ?? const [])) {
          final item = Map<String, dynamic>.from(raw as Map);
          requested[item['purchaseItemId'].toString()] = _num(item['quantity']);
        }
        for (final item in items) {
          final outstanding = _num(item['quantity']) - _num(item['receivedQuantity']);
          final take = requested.isEmpty
              ? outstanding
              : (requested[item['id']] ?? 0).clamp(0, outstanding).toDouble();
          if (take <= 0) continue;
          item['receivedQuantity'] = _num(item['receivedQuantity']) + take;
          final productId = item['productId'].toString();
          _stock[productId] = (_stock[productId] ?? 0) + take;
        }
        final fullyReceived = items.every(
          (item) => _num(item['receivedQuantity']) >= _num(item['quantity']),
        );
        purchase['status'] = fullyReceived ? 'RECEIVED' : 'PARTIALLY_RECEIVED';
        return purchase;
      default:
        throw AppError(
          code: ErrorCodes.validation,
          message: 'Unknown action "$action".',
          status: 400,
        );
    }
  }

  Map<String, dynamic> _createPurchaseReturn(Map<String, dynamic> data) {
    final purchase = _find(_purchases, data['purchaseId'].toString());
    final items = (purchase['items'] as List).cast<Map<String, dynamic>>();

    final lines = <Map<String, dynamic>>[];
    var total = 0.0;
    for (final raw in (data['items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final purchaseItemId = item['purchaseItemId'].toString();
      final quantity = _num(item['quantity']);
      final purchaseItem = items.firstWhere(
        (pi) => pi['id'] == purchaseItemId,
        orElse: () => <String, dynamic>{},
      );
      if (purchaseItem.isEmpty) continue;
      final amount = quantity * _num(purchaseItem['price']);
      total += amount;
      final productId = purchaseItem['productId'].toString();
      _stock[productId] = (_stock[productId] ?? 0) - quantity;
      lines.add({
        'id': 'pri${_nextId()}',
        'purchaseItemId': purchaseItemId,
        'productName': purchaseItem['productName'],
        'quantity': quantity,
        'amount': amount,
      });
    }

    final purchaseReturn = {
      'id': _nextId(),
      'returnNumber': 'PR-${90 + _purchaseReturns.length + 1}',
      'purchaseId': purchase['id'],
      'purchaseNumber': purchase['purchaseNumber'],
      'reason': data['reason'],
      'status': 'COMPLETED',
      'totalAmount': total,
      'items': lines,
      'createdAt': _now(),
    };

    _purchaseReturns.insert(0, purchaseReturn);
    return purchaseReturn;
  }

  // --------------------------------------------------------------- transfers

  // Mirrors the real API: only `toWarehouseId` is known at request time —
  // `fromWarehouseId` stays unset until an admin approves it, which this app
  // never does, so most transfers created here have no source at all. Seed
  // data below injects an already-approved-looking record directly, to give
  // the ship/receive actions something to demo.
  Map<String, dynamic> _createTransfer(Map<String, dynamic> data) {
    final lines = <Map<String, dynamic>>[];
    for (final raw in (data['items'] as List? ?? const [])) {
      final item = Map<String, dynamic>.from(raw as Map);
      final productId = item['productId'].toString();
      lines.add({
        'id': 'ti${_nextId()}',
        'productId': productId,
        'productName': _product(productId)['name'],
        'sku': _product(productId)['sku'],
        'quantity': _num(item['requestedQuantity'] ?? item['quantity']),
      });
    }

    final from = data['fromWarehouseId']?.toString();
    final to = data['toWarehouseId'].toString();
    final transfer = {
      'id': _nextId(),
      'transferNumber': 'T-${210 + _transfers.length + 1}',
      'status': 'PENDING',
      'fromWarehouseId': from,
      'fromWarehouseName':
          from == null ? null : (from == warehouseId ? warehouseName : 'Store #$from'),
      'toWarehouseId': to,
      'toWarehouseName': to == warehouseId ? warehouseName : 'Store #$to',
      'transferDate': data['transferDate'] ?? _today(),
      'notes': data['notes'],
      'items': lines,
      'createdAt': _now(),
    };

    _transfers.insert(0, transfer);
    return transfer;
  }

  Map<String, dynamic> _transferAction(
    Map<String, dynamic> transfer,
    String action,
  ) {
    final outgoing = transfer['fromWarehouseId'] == warehouseId;
    switch (action) {
      case 'ship':
        transfer['status'] = 'SHIPPED';
        if (outgoing) {
          for (final raw in (transfer['items'] as List)) {
            final item = Map<String, dynamic>.from(raw as Map);
            final id = item['productId'].toString();
            _stock[id] = (_stock[id] ?? 0) - _num(item['quantity']);
          }
        }
        return transfer;
      case 'receive':
        transfer['status'] = 'RECEIVED';
        if (!outgoing) {
          for (final raw in (transfer['items'] as List)) {
            final item = Map<String, dynamic>.from(raw as Map);
            final id = item['productId'].toString();
            _stock[id] = (_stock[id] ?? 0) + _num(item['quantity']);
          }
        }
        return transfer;
      case 'cancel':
        transfer['status'] = 'CANCELLED';
        return transfer;
      default:
        throw AppError(
          code: ErrorCodes.validation,
          message: 'Unknown action "$action".',
          status: 400,
        );
    }
  }

  // ------------------------------------------------------------- adjustments

  Map<String, dynamic> _adjust(Map<String, dynamic> data) {
    final productId = data['productId'].toString();
    final delta = _num(data['quantity']);
    final current = _stock[productId] ?? 0;
    if (current + delta < 0) {
      throw AppError(
        code: ErrorCodes.insufficientStock,
        message: 'Only ${current.toInt()} on hand — cannot write off more.',
        status: 422,
      );
    }
    _stock[productId] = current + delta;
    return {
      'id': _nextId(),
      'productId': productId,
      'quantity': delta,
      'reason': data['reason'],
      'createdAt': _now(),
    };
  }

  // -------------------------------------------------------------------- seed

  /// A little history so the lists aren't all empty on first look.
  void _seed() {
    if (_seeded) return;
    _seeded = true;

    // A completed sale from earlier today.
    final completed = _createSale({
      'items': [
        {'productId': 'p1', 'quantity': '2', 'price': '899.00'},
        {'productId': 'p8', 'quantity': '3', 'price': '149.00'},
      ],
      'customerId': 'c1',
      'channel': 'POS',
    });
    _saleAction(completed, 'confirm');
    _saleAction(completed, 'complete');

    // One still open on the floor.
    final confirmed = _createSale({
      'items': [
        {'productId': 'p2', 'quantity': '1', 'price': '349.00'},
        {'productId': 'p12', 'quantity': '2', 'price': '459.00'},
      ],
      'customerId': 'c3',
      'channel': 'POS',
    });
    _saleAction(confirmed, 'confirm');

    // A purchase mid-flight, so "Receive stock" has something to act on.
    final ordered = _createPurchase({
      'supplierId': 's1',
      'items': [
        {'productId': 'p6', 'quantity': '12', 'price': '420.00'},
        {'productId': 'p13', 'quantity': '10', 'price': '300.00'},
      ],
      'notes': 'Monthly resupply',
    });
    _purchaseAction(ordered, 'confirm', const {});

    // A fully received one, so supplier returns have a candidate.
    final received = _createPurchase({
      'supplierId': 's2',
      'items': [
        {'productId': 'p5', 'quantity': '4', 'price': '1100.00'},
      ],
    });
    _purchaseAction(received, 'confirm', const {});
    _purchaseAction(received, 'receive', const {});

    // One transfer each way.
    _createTransfer({
      'fromWarehouseId': warehouseId,
      'toWarehouseId': '6',
      'items': [
        {'productId': 'p14', 'quantity': '20'},
      ],
      'notes': 'Sleeves for the airport kiosk',
    });
    _createTransfer({
      'fromWarehouseId': '7',
      'toWarehouseId': warehouseId,
      'items': [
        {'productId': 'p10', 'quantity': '15'},
      ],
    });
    _transfers.last['status'] = 'SHIPPED';
  }
}
