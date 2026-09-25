import '../../core/json.dart';

/// A customer's credit position at this moment — `GET
/// /credit/customers/{id}/summary`. Read-only preview, same spirit as
/// `PricingQuote`: nothing here is committed until a sale/payment actually
/// posts.
class CreditSummary {
  const CreditSummary({
    required this.currentBalance,
    this.creditLimit,
    this.availableCredit,
  });

  /// What the customer currently owes.
  final double currentBalance;

  /// Null means unlimited — no per-customer limit *and* no tenant default
  /// configured. Never treat null as zero.
  final double? creditLimit;

  /// Null exactly when [creditLimit] is — there's nothing to be "available
  /// against" without a limit.
  final double? availableCredit;

  bool get hasLimit => creditLimit != null;

  factory CreditSummary.fromJson(Map<String, dynamic> json) => CreditSummary(
        currentBalance: asDouble(json['currentBalance']),
        creditLimit: asDoubleOrNull(json['creditLimit']),
        availableCredit: asDoubleOrNull(json['availableCredit']),
      );
}

/// A customer's credit *settings*, not just their current position —
/// `GET /credit/customers/{id}` (`CREDIT.VIEW`) / the response of `PATCH
/// .../{id}` (`CREDIT.MANAGE`). Distinct from [CreditSummary]: this is the
/// admin-facing config (the limit itself, the settlement day), not the
/// checkout-facing preview (available credit).
class CreditConfig {
  const CreditConfig({
    required this.customerId,
    required this.customerName,
    required this.currentBalance,
    this.creditLimit,
    this.settlementDay,
  });

  final String customerId;
  final String customerName;
  final double currentBalance;

  /// Null means unlimited — see [CreditSummary.creditLimit].
  final double? creditLimit;

  /// Day-of-month (1–28) for the monthly settlement reminder, or null if
  /// not configured. Capped at 28 server-side so it's valid every month.
  final int? settlementDay;

  factory CreditConfig.fromJson(Map<String, dynamic> json) => CreditConfig(
        customerId: firstString(json, ['customerId']) ?? '',
        customerName: asString(json['customerName']) ?? '',
        currentBalance: asDouble(json['currentBalance']),
        creditLimit: asDoubleOrNull(json['creditLimit']),
        settlementDay: asNum(json['settlementDay'])?.toInt(),
      );
}

/// One row of a customer's credit ledger — `type`/`direction` decide how it
/// reads in a statement-of-account view (see [label]/[signedAmount]).
/// Doubles as the response of `POST /credit/customers/{id}/payments`: that
/// endpoint returns the transaction it just created, same shape as every
/// row `GET .../transactions` lists — not the trimmed sample
/// `credit_androidChanges.md` §4 shows.
class CreditTransaction {
  const CreditTransaction({
    required this.id,
    required this.type,
    required this.direction,
    required this.amount,
    required this.runningBalance,
    required this.createdAt,
    this.paymentMethod,
    this.referenceType,
    this.referenceId,
    this.remarks,
  });

  final String id;

  /// `OPENING` | `SALE_CHARGE` | `PAYMENT` | `CREDIT_NOTE` | `ADJUSTMENT`.
  final String type;

  /// `IN` reduces what the customer owes (a payment, a credit note); `OUT`
  /// increases it (the opening balance, a sale put on credit).
  final String direction;

  final double amount;

  /// How a `PAYMENT` was actually received (`CASH`/`UPI`/…) or a
  /// `SALE_CHARGE`'s method (`CREDIT`, always). Null for `OPENING`/
  /// `CREDIT_NOTE`/`ADJUSTMENT` rows — there's no payment method to speak
  /// of for those.
  final String? paymentMethod;

  /// `SALE` | `SALE_RETURN` | `MANUAL` | null.
  final String? referenceType;
  final String? referenceId;
  final String? remarks;

  /// The customer's running due immediately after this row posted.
  final double runningBalance;

  final String createdAt;

  bool get isOut => direction.toUpperCase() == 'OUT';

  /// Signed the way a statement-of-account reads: an `OUT` row (the
  /// customer now owes more) shown as `+`, an `IN` row (they owe less) as
  /// `-` — see credit_androidChanges.md §5.
  double get signedAmount => isOut ? amount : -amount;

  String get label => switch (type.toUpperCase()) {
        'SALE_CHARGE' => 'Sale',
        'PAYMENT' => 'Payment',
        'CREDIT_NOTE' => 'Credit Note',
        'OPENING' => 'Opening Balance',
        'ADJUSTMENT' => 'Adjustment',
        _ => type,
      };

  factory CreditTransaction.fromJson(Map<String, dynamic> json) =>
      CreditTransaction(
        id: firstString(json, ['id']) ?? '',
        type: asString(json['type']) ?? '',
        direction: asString(json['direction']) ?? '',
        amount: asDouble(json['amount']),
        paymentMethod: asString(json['paymentMethod']),
        referenceType: asString(json['referenceType']),
        referenceId: firstString(json, ['referenceId']),
        remarks: asString(json['remarks']),
        runningBalance: asDouble(json['runningBalance']),
        createdAt: firstString(json, ['createdAt', 'created_at']) ?? '',
      );
}
