import '../../core/json.dart';

/// The coupon actually resolved by the server, with the amount it removed.
///
/// Only ever present when a valid, applicable coupon was sent — an invalid or
/// inapplicable code makes `POST /pricing/quote` fail outright rather than
/// come back with this null, so callers read the coupon off a success
/// response, not a null-check on it. Set for *either* an ORDER-scope coupon
/// (applied once to [PricingQuote.grandTotal]) or a PRODUCT/CATEGORY-scope
/// one (applied per matching line — [amount] is the sum across those lines;
/// see [QuoteLine.discounts] for which lines it actually hit).
class PricingQuoteCoupon {
  const PricingQuoteCoupon({
    required this.couponId,
    required this.code,
    required this.amount,
  });

  final String couponId;
  final String code;
  final double amount;

  factory PricingQuoteCoupon.fromJson(Map<String, dynamic> json) =>
      PricingQuoteCoupon(
        couponId: asString(json['couponId']) ?? '',
        code: asString(json['code']) ?? '',
        amount: asDouble(json['amount']),
      );
}

/// One automatic Discount or PRODUCT/CATEGORY-scope coupon reduction applied
/// to a single line. Exactly one of [discountId]/[couponId] is set — an
/// ORDER-scope coupon never appears here, only once on
/// [PricingQuote.coupon] (see `promotion.service.ts`).
class QuoteLineDiscount {
  const QuoteLineDiscount({
    required this.name,
    required this.amount,
    this.discountId,
    this.couponId,
  });

  final String? discountId;
  final String? couponId;
  final String name;
  final double amount;

  bool get isCoupon => couponId != null;

  factory QuoteLineDiscount.fromJson(Map<String, dynamic> json) =>
      QuoteLineDiscount(
        discountId: asString(json['discountId']),
        couponId: asString(json['couponId']),
        name: asString(json['name']) ?? '',
        amount: asDouble(json['amount']),
      );
}

/// One CGST/SGST/IGST/CESS component of a line's (or charge's) tax — mirrors
/// `SaleItemTax`'s shape exactly (`lib/data/models/sale.dart`'s
/// `SaleItemTax`), since a quote line and a persisted sale line render the
/// same breakdown, not two different shapes for the same data.
class QuoteLineTaxComponent {
  const QuoteLineTaxComponent({
    required this.component,
    required this.ratePercent,
    required this.amount,
    this.taxRateId,
  });

  final String? taxRateId;
  final String component;
  final double ratePercent;
  final double amount;

  factory QuoteLineTaxComponent.fromJson(Map<String, dynamic> json) =>
      QuoteLineTaxComponent(
        taxRateId: asString(json['taxRateId']),
        component: asString(json['component']) ?? '',
        ratePercent: asDouble(json['ratePercent']),
        amount: asDouble(json['amount']),
      );
}

/// One cart line exactly as the server priced it: [lineSubtotal] before any
/// reduction, every [discounts] entry that matched it (automatic Discounts,
/// stacked in priority order, plus a PRODUCT/CATEGORY-scope coupon), and
/// [lineTotal] after. This is the authoritative per-line breakdown — the
/// same numbers a cashier-entered price/discount on the cart line are only
/// an unverified guess of, until this comes back.
class QuoteLine {
  const QuoteLine({
    required this.productId,
    required this.quantity,
    required this.unitPrice,
    required this.lineSubtotal,
    required this.lineTotal,
    this.discounts = const [],
    this.tax = 0,
    this.taxes = const [],
  });

  final String productId;
  final double quantity;
  final double unitPrice;

  /// `unitPrice * quantity`, before any discount on this line.
  final double lineSubtotal;

  final List<QuoteLineDiscount> discounts;

  /// After every discount in [discounts] is applied.
  final double lineTotal;

  /// Computed on [lineTotal] (post-discount/coupon). Whether this is already
  /// included in [lineTotal] or owed on top of it depends on
  /// [PricingQuote.taxInclusive] — see that field.
  final double tax;

  /// The CGST/SGST/IGST/CESS breakdown that sums to [tax].
  final List<QuoteLineTaxComponent> taxes;

  double get discountTotal =>
      discounts.fold<double>(0, (sum, d) => sum + d.amount);

  bool get isDiscounted => discountTotal > 0;

  factory QuoteLine.fromJson(Map<String, dynamic> json) => QuoteLine(
        productId: asString(json['productId']) ?? '',
        quantity: asDouble(json['quantity']),
        unitPrice: asDouble(json['unitPrice']),
        lineSubtotal: asDouble(json['lineSubtotal']),
        lineTotal: asDouble(json['lineTotal']),
        discounts: asMapList(json['discounts'])
            .map(QuoteLineDiscount.fromJson)
            .toList(),
        tax: asDouble(json['tax']),
        taxes: asMapList(json['taxes'])
            .map(QuoteLineTaxComponent.fromJson)
            .toList(),
      );
}

/// One extra charge (shipping, packaging, …) the server resolved and taxed.
class QuoteCharge {
  const QuoteCharge({
    required this.extraChargeId,
    required this.name,
    required this.amount,
    required this.taxAmount,
    this.taxRateId,
  });

  final String extraChargeId;
  final String? taxRateId;
  final String name;
  final double amount;
  final double taxAmount;

  factory QuoteCharge.fromJson(Map<String, dynamic> json) => QuoteCharge(
        extraChargeId: asString(json['extraChargeId']) ?? '',
        taxRateId: asString(json['taxRateId']),
        name: asString(json['name']) ?? '',
        amount: asDouble(json['amount']),
        taxAmount: asDouble(json['taxAmount']),
      );
}

/// Response of `POST /pricing/quote` — a read-only pricing preview: discounts,
/// coupon and tax are recomputed server-side, nothing is persisted or
/// redeemed.
///
/// Mirrors `QuoteView` in `modules/pricing/types/promotion.types.ts` on the
/// server field-for-field. One thing it deliberately does *not* carry,
/// because the server doesn't accept it at this endpoint: a manual
/// order-level discount — `discountAmount`/`discountPercent` sent in the
/// request aren't in `quoteSchema` and are silently dropped; only automatic
/// Discounts and a coupon code affect this response.
/// See INVOICE_CALCULATION_LOGIC.md for the full contract audit.
class PricingQuote {
  const PricingQuote({
    required this.subtotal,
    required this.lineDiscountTotal,
    required this.grandTotal,
    this.lines = const [],
    this.coupon,
    this.charges = const [],
    this.chargesTotal,
    this.chargesTaxTotal,
    this.taxTotal,
    this.taxInclusive = false,
  });

  /// Sum of every line's [QuoteLine.lineSubtotal] — before any discount.
  final double subtotal;

  /// Sum of every line's [QuoteLine.discountTotal] — every automatic
  /// Discount and PRODUCT/CATEGORY-scope coupon reduction combined,
  /// regardless of which line or which discount/coupon it came from.
  final double lineDiscountTotal;

  /// The amount the customer actually pays. Already correctly resolved by
  /// the server for both tax modes — see [taxInclusive] — so this is always
  /// the number to charge/display as the total, never `subtotal -
  /// lineDiscountTotal + taxTotal + chargesTotal` computed by hand (that
  /// double-counts tax when [taxInclusive] is true).
  final double grandTotal;

  /// Per-line breakdown — see [QuoteLine].
  final List<QuoteLine> lines;

  /// Resolved coupon, if one was sent and accepted (either scope).
  final PricingQuoteCoupon? coupon;

  /// Extra charges the server resolved, each with its own tax — empty
  /// unless `extraChargeIds` was sent in the request.
  final List<QuoteCharge> charges;

  /// Sum of [charges]' amounts — 0, never null, when there are none.
  final double? chargesTotal;

  /// Sum of [charges]' tax — 0, never null, when there are none.
  final double? chargesTaxTotal;

  /// Sum of every line's tax plus every charge's tax — shown for the GST
  /// breakdown. Not always additive into [grandTotal]: see [taxInclusive].
  final double? taxTotal;

  /// Whether this quote was computed under tax-inclusive pricing — echoes
  /// the tenant's `TenantSetting.taxInclusivePricing` (or an explicit
  /// override on the request). When `true`, [taxTotal] is already folded
  /// into every line's [QuoteLine.lineTotal] and into [grandTotal] — show it
  /// as "tax included", never add it on top. When `false`, [taxTotal] is a
  /// genuine add-on the server already summed into [grandTotal] — safe to
  /// show as a normal additive line in a breakdown. Mirrors
  /// `Sale.taxInclusive`/`SaleView.taxInclusive` for a persisted sale
  /// (`lib/data/models/sale.dart`).
  final bool taxInclusive;

  /// Every *automatic* Discount name that reduced at least one line, with the
  /// combined amount it removed across all lines it touched — e.g. a
  /// category-wide discount applied to three lines is shown once, summed,
  /// instead of once per line. Coupon reductions are excluded — those are
  /// already named by [coupon] and would otherwise be double-listed.
  Map<String, double> get discountBreakdown {
    final byName = <String, double>{};
    for (final line in lines) {
      for (final discount in line.discounts) {
        if (discount.isCoupon) continue;
        byName[discount.name] = (byName[discount.name] ?? 0) + discount.amount;
      }
    }
    return byName;
  }

  /// The portion of [lineDiscountTotal] contributed by a PRODUCT/CATEGORY-
  /// scope coupon — 0 for an ORDER-scope coupon (which reduces [grandTotal]
  /// directly instead, never touching a line) or when there's no coupon at
  /// all. Equal to [coupon]'s amount whenever it's non-zero.
  double get lineCouponTotal => lines.fold<double>(
        0,
        (sum, line) => sum +
            line.discounts
                .where((d) => d.isCoupon)
                .fold<double>(0, (s, d) => s + d.amount),
      );

  /// [lineDiscountTotal] with any coupon contribution backed out — automatic
  /// Discounts only, safe to show next to the Coupon row without the two
  /// double-counting the same reduction for a PRODUCT/CATEGORY-scope coupon
  /// (whose amount is folded into [lineDiscountTotal] by the server, not
  /// additional to it — see `promotion.service.ts`).
  double get autoDiscountTotal => lineDiscountTotal - lineCouponTotal;

  factory PricingQuote.fromJson(Map<String, dynamic> json) {
    final coupon = asMap(json['coupon']);
    return PricingQuote(
      subtotal: asDouble(json['subtotal']),
      lineDiscountTotal: asDouble(json['lineDiscountTotal']),
      grandTotal: asDouble(json['grandTotal']),
      lines: asMapList(json['lines']).map(QuoteLine.fromJson).toList(),
      coupon: coupon == null ? null : PricingQuoteCoupon.fromJson(coupon),
      charges: asMapList(json['charges']).map(QuoteCharge.fromJson).toList(),
      chargesTotal: asDoubleOrNull(json['chargesTotal']),
      chargesTaxTotal: asDoubleOrNull(json['chargesTaxTotal']),
      taxTotal: asDoubleOrNull(json['taxTotal']),
      taxInclusive: asBool(json['taxInclusive']),
    );
  }
}
