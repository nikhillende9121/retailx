/// Default backend — the hosted portal. Overridable at runtime from the login
/// screen, so the same build can point at localhost or staging.
///
/// HTTPS, so it works over mobile data and needs no cleartext exemption. For a
/// local dev server use `http://192.168.1.7:3000/api/v1/` (LAN, physical device)
/// or `http://10.0.2.2:3000/api/v1/` (emulator to host).
// const String kDefaultApiBaseUrl = 'https://busyos-hazel.vercel.app/api/v1/';
const String kDefaultApiBaseUrl = 'http://103.205.142.172:3000/api/v1/';
/// Permission codes (MOBILE_API_GUIDE.md §5 and §7).
class Perm {
  Perm._();

  static const saleView = 'SALE.VIEW';
  static const saleCreate = 'SALE.CREATE';
  static const saleConfirm = 'SALE.CONFIRM';
  static const saleUpdate = 'SALE.UPDATE';
  static const saleExchange = 'SALE.EXCHANGE';
  static const saleShip = 'SALE.SHIP';
  static const saleDeliver = 'SALE.DELIVER';

  static const saleReturnView = 'SALE_RETURN.VIEW';
  static const saleReturnCreate = 'SALE_RETURN.CREATE';

  static const purchaseView = 'PURCHASE.VIEW';
  static const purchaseCreate = 'PURCHASE.CREATE';
  static const purchaseUpdate = 'PURCHASE.UPDATE';
  static const purchaseReceive = 'PURCHASE.RECEIVE';

  static const purchaseReturnView = 'PURCHASE_RETURN.VIEW';
  static const purchaseReturnCreate = 'PURCHASE_RETURN.CREATE';

  static const inventoryView = 'INVENTORY.VIEW';
  static const inventoryAdjust = 'INVENTORY.ADJUST';

  static const transferView = 'STOCK_TRANSFER.VIEW';
  static const transferCreate = 'STOCK_TRANSFER.CREATE';
  static const transferApprove = 'STOCK_TRANSFER.APPROVE';
  static const transferShip = 'STOCK_TRANSFER.SHIP';
  static const transferReceive = 'STOCK_TRANSFER.RECEIVE';
  static const transferUpdate = 'STOCK_TRANSFER.UPDATE';

  static const warehouseView = 'WAREHOUSE.VIEW';

  static const customerView = 'CUSTOMER.VIEW';
  static const customerCreate = 'CUSTOMER.CREATE';

  static const customerGroupView = 'CUSTOMER_GROUP.VIEW';

  static const creditView = 'CREDIT.VIEW';
  static const creditManage = 'CREDIT.MANAGE';
}

/// Plan feature codes. A tenant's plan gates whole modules independently of
/// role permissions, so both are checked before a nav item is shown.
class Feature {
  Feature._();

  static const sales = 'SALES';
  static const saleReturn = 'SALE_RETURN';
  static const saleExchange = 'SALE_EXCHANGE';
  static const purchase = 'PURCHASE';
  static const purchaseReturn = 'PURCHASE_RETURN';
  static const inventory = 'INVENTORY';
  static const stockTransfer = 'STOCK_TRANSFER';

  static const customer = 'CUSTOMER';

  /// Group-based pricing/discount scoping — see `PriceList`/`Discount`'s
  /// `customerGroupId` on the backend. Meaningless without [customer] also
  /// being enabled, since a group is a property of a customer.
  static const customerGroup = 'CUSTOMER_GROUP';

  /// Gates the checkout coupon field. DISCOUNT and PRICE_LIST are also real
  /// feature codes on the backend, but neither has a distinct client-facing
  /// UI element of its own to gate — line discounts are just server-computed
  /// numbers the app displays, and price lists apply automatically with no
  /// screen for a cashier to interact with either way.
  static const coupon = 'COUPON';

  /// Gates `CREDIT` in the checkout payment-method picker, the due/limit
  /// display, and the customer-credit screens — see
  /// `credit_androidChanges.md`. A UX convenience only, same as every other
  /// entry here: the server independently 403s anything credit-related for
  /// a tenant without this feature regardless of what the app shows.
  static const creditPayment = 'CREDIT_PAYMENT';
}

/// Sale lifecycle states.
class SaleStatus {
  SaleStatus._();

  static const draft = 'DRAFT';
  static const confirmed = 'CONFIRMED';
  static const processing = 'PROCESSING';
  static const packed = 'PACKED';
  static const shipped = 'SHIPPED';
  static const delivered = 'DELIVERED';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';

  /// Statuses a sale must be in before it can be returned or exchanged.
  static const returnable = [confirmed, completed, delivered];
}

class PurchaseStatus {
  PurchaseStatus._();

  static const draft = 'DRAFT';
  static const ordered = 'ORDERED';
  static const partiallyReceived = 'PARTIALLY_RECEIVED';
  static const received = 'RECEIVED';
  static const cancelled = 'CANCELLED';

  static const returnable = [partiallyReceived, received];
}

/// DRAFT -> APPROVED (admin picks the source store) -> IN_TRANSIT (shipped)
/// -> COMPLETED (received). There is no PENDING/SHIPPED/RECEIVED status on
/// the server — a transfer is either DRAFT, APPROVED, IN_TRANSIT, COMPLETED,
/// or CANCELLED.
class TransferStatus {
  TransferStatus._();

  static const draft = 'DRAFT';
  static const approved = 'APPROVED';
  static const inTransit = 'IN_TRANSIT';
  static const completed = 'COMPLETED';
  static const cancelled = 'CANCELLED';
}

/// Settlement methods offered when an exchange leaves a balance to collect —
/// matches the server's actual `paymentMethod` enum
/// (`sale-exchange.schema.ts`/`sale.schema.ts`) exactly. `STORE_CREDIT` used
/// to be listed here but was never a real accepted value — picking it would
/// 400 on submit; corrected to the enum's real 5 values. `CREDIT` is
/// deliberately excluded here: settling what a customer already owes *by*
/// putting it back on credit is meaningless (see credit_androidChanges.md
/// §4) — it only ever appears in [kSalePaymentMethods], for the sale itself.
const List<String> kPaymentMethods = [
  'CASH',
  'CARD',
  'BANK_TRANSFER',
  'UPI',
  'CHEQUE',
];

/// Same 5 real methods, plus `CREDIT` — offered on a sale itself (not a
/// settlement), and only when the tenant has `Feature.creditPayment` and a
/// customer is selected (a walk-in sale can't go on credit).
const List<String> kSalePaymentMethods = [...kPaymentMethods, 'CREDIT'];

/// Sale channel this app always creates in — it is a till, not a web store.
const String kPosChannel = 'POS';

const int kPageSize = 20;
