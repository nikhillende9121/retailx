import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/json.dart';
import '../api_client.dart';
import '../models/pricing_quote.dart';
import 'sales_repository.dart' show ChargeInput, LineInput;

class PricingRepository {
  PricingRepository(this._api);

  final ApiClient _api;

  /// Read-only preview — no persistence, no coupon redemption — so it's safe
  /// to call on every cart or coupon change to keep the totals live.
  ///
  /// Sends the full checkout state so the server can compute everything:
  /// line-level discounts, sale-level discount, coupon, extra charges.
  /// Optional fields are omitted from the body when zero/null so the payload
  /// stays backward-compatible with older server versions.
  Future<PricingQuote> quote({
    required String warehouseId,
    required List<LineInput> lines,
    String? customerId,
    String? couponCode,
    double discountAmount = 0,
    double? discountPercent,
    List<ChargeInput>? charges,
    // Same default as SalesRepository.create() — the checkout screen this
    // quote previews is a POS till, so the channel it'll actually be
    // charged under is always POS unless a caller says otherwise. Sent
    // unconditionally (not just when non-default) since the server uses it
    // to auto-resolve any extra charges configured for this channel when
    // `charges` isn't given explicitly (see promotion.service.ts's
    // resolveSaleCharges) — omitting it would under-preview those charges
    // here while `POST /sales` still applies them at charge time.
    String channel = kPosChannel,
  }) async {
    final body = <String, dynamic>{
      'warehouseId': warehouseId,
      'channel': channel,
      'lines': [
        for (final line in lines)
          {
            'productId': line.productId,
            'quantity': qtyForApi(line.quantity),
            'unitPrice': moneyForApi(line.price),
            if (line.discount > 0)
              'discountAmount': moneyForApi(line.discount),
          },
      ],
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
    final data = await _api.post('pricing/quote', body: body);
    return PricingQuote.fromJson(asMap(data) ?? const {});
  }

  /// The real, price-list-resolved price for one product — the same
  /// resolution `POST /sales`/`POST /sale-exchanges` use server-side
  /// (`resolveItemPrice`), for a caller that needs it *before* submitting.
  ///
  /// `GET /products` (what the product picker calls) carries no price field
  /// at all — pricing is a separate concern, resolved per warehouse/customer/
  /// quantity, not a flat catalog attribute — so this is the only way to
  /// show a real price for a product added outside the checkout till (which
  /// gets it for free from `/inventory/balance`'s embedded "buy 1" price).
  /// Throws (404-shaped `AppError`) when the product has no price configured
  /// for this warehouse at all — same as the create endpoints would.
  Future<double> resolvePrice({
    required String productId,
    required String warehouseId,
    String? customerGroupId,
    String? customerId,
    double quantity = 1,
  }) async {
    final data = await _api.get('pricing/resolve', query: {
      'productId': productId,
      'warehouseId': warehouseId,
      if (customerGroupId != null && customerGroupId.isNotEmpty)
        'customerGroupId': customerGroupId,
      if (customerId != null && customerId.isNotEmpty)
        'customerId': customerId,
      'quantity': qtyForApi(quantity),
    });
    return asDouble(asMap(data)?['price']);
  }
}
