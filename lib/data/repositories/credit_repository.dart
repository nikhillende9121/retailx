import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../core/json.dart';
import '../api_client.dart';
import '../models/credit.dart';
import '../models/paged.dart';

/// See `credit_androidChanges.md`. Every call here is gated by
/// `Feature.creditPayment` client-side (a UX convenience — the server
/// independently 403s `FEATURE_NOT_ENABLED` regardless) and by
/// `Perm.creditView`/`Perm.creditManage` per method below.
class CreditRepository {
  CreditRepository(this._api);

  final ApiClient _api;

  /// `CREDIT.VIEW`. Call the moment a customer is picked at checkout (if
  /// credit is enabled) so the due/limit shows before `CREDIT` is even
  /// tapped, not only after.
  Future<CreditSummary> summary(String customerId) async {
    final data = await _api.get('credit/customers/$customerId/summary');
    return CreditSummary.fromJson(asMap(data) ?? const {});
  }

  /// `CREDIT.MANAGE`. Records money collected against what the customer
  /// already owes — unrelated to any specific sale. [paymentMethod] is how
  /// the settlement was *received* (`CASH`/`UPI`/…), never `CREDIT` itself.
  Future<CreditTransaction> recordPayment(
    String customerId, {
    required double amount,
    required String paymentMethod,
    String? remarks,
  }) async {
    final body = <String, dynamic>{
      'amount': moneyForApi(amount),
      'paymentMethod': paymentMethod,
    };
    if (remarks != null && remarks.trim().isNotEmpty) {
      body['remarks'] = remarks.trim();
    }
    final data = await _api.post(
      'credit/customers/$customerId/payments',
      body: body,
    );
    return CreditTransaction.fromJson(asMap(data) ?? const {});
  }

  /// `CREDIT.VIEW`. Statement-of-account, newest first.
  Future<PagedList<CreditTransaction>> transactions(
    String customerId, {
    int page = 1,
    int pageSize = kPageSize,
  }) async {
    final data = await _api.get(
      'credit/customers/$customerId/transactions',
      query: {'page': page, 'pageSize': pageSize},
    );
    return PagedList.from(data, CreditTransaction.fromJson);
  }

  /// `CREDIT.VIEW`. The admin-facing config (limit + settlement day), not
  /// the checkout-facing [summary].
  Future<CreditConfig> config(String customerId) async {
    final data = await _api.get('credit/customers/$customerId');
    return CreditConfig.fromJson(asMap(data) ?? const {});
  }

  /// `CREDIT.MANAGE`. `creditLimit` is required on every call (the server
  /// schema has no optional variant of it) — pass `null` explicitly to mean
  /// "no limit," never omit it meaning "leave unchanged." `settlementDay`
  /// is genuinely optional: omit it to leave the existing value alone.
  Future<CreditConfig> updateConfig(
    String customerId, {
    required double? creditLimit,
    int? settlementDay,
  }) async {
    final body = <String, dynamic>{
      'creditLimit': creditLimit == null ? null : moneyForApi(creditLimit),
    };
    if (settlementDay != null) body['settlementDay'] = settlementDay;
    final data = await _api.patch(
      'credit/customers/$customerId',
      body: body,
    );
    return CreditConfig.fromJson(asMap(data) ?? const {});
  }

  /// `CREDIT.MANAGE`. A customer's starting due when they're first put on
  /// credit — not a settlement, an `OPENING`-type ledger entry. Meant to be
  /// used once per customer; the server doesn't itself prevent a second
  /// call, but recording it twice would double their opening due.
  Future<CreditTransaction> recordOpeningBalance(
    String customerId, {
    required double amount,
    String? remarks,
  }) async {
    final body = <String, dynamic>{'amount': moneyForApi(amount)};
    if (remarks != null && remarks.trim().isNotEmpty) {
      body['remarks'] = remarks.trim();
    }
    final data = await _api.post(
      'credit/customers/$customerId/opening-balance',
      body: body,
    );
    return CreditTransaction.fromJson(asMap(data) ?? const {});
  }
}
