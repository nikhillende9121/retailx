# Credit Payment Module — Android App Changes

Companion to `Docs/credit_module_plan.md` (the full backend design — read
that first for *why*; this doc is the *what changed for the app*, in the
same format as `deliveryAssignment_androidChanges.md`). Status: **planned,
not yet implemented** — nothing described here exists in the API yet.

Covers: how the app learns whether Credit is enabled for the logged-in
tenant, the new "due amount / max limit" display required before a cashier
confirms a Credit sale, the new endpoints for viewing and settling a
customer's credit, and the new error the app must handle.

---

## 0. Is Credit enabled for this tenant?

`GET /api/v1/auth/me` already returns an `enabledFeatures: string[]` array
(`modules/auth/types/auth.types.ts`) alongside `permissions` — the app
should already be reading this array to hide nav items/buttons for any
feature-gated module (`PRODUCT`, `CATEGORY`, etc.). Add one more check:

```kotlin
val creditEnabled = me.enabledFeatures.contains("CREDIT_PAYMENT")
```

When `false`: don't show `CREDIT` in the payment-method picker, don't show
the Credit Report screen/tab, don't show the "existing due" field on the
customer form. When `true`, everything below applies. This is the same
gating rule as every other module — a UX convenience, not a security
boundary; the server independently rejects anything credit-related for a
tenant without the feature (`403 FEATURE_NOT_ENABLED`).

The app also needs `CREDIT.VIEW` in its `permissions` array to call the
summary/transactions endpoints below — this should be part of the default
Cashier/Store Manager role, but if a 403 `PERMISSION_DENIED` comes back on
these calls for an otherwise-credit-enabled tenant, that's why.

---

## 1. Payment method picker: `CREDIT` is now selectable

`CASH | CARD | BANK_TRANSFER | UPI | CHEQUE` are unchanged. `CREDIT` is a
value that already existed server-side but the app has had no reason to
show — from now on, show it whenever `creditEnabled` is true **and** a
customer has been selected for the sale (credit requires a customer; there
is no "walk-in credit sale").

## 2. New: `GET /api/v1/credit/customers/{customerId}/summary`

Call this the moment a customer is picked at checkout, if `creditEnabled`.
Use it to show the due/limit inline under the `CREDIT` option — **before**
the cashier taps it, not only after:

```
GET /api/v1/credit/customers/24/summary
Authorization: Bearer <accessToken>
```

```json
{
  "success": true,
  "data": {
    "currentBalance": "4200.00",
    "creditLimit": "10000.00",
    "availableCredit": "5800.00"
  }
}
```

`creditLimit` and `availableCredit` are `null` when the customer has no
per-customer limit and the tenant has no default configured — treat `null`
as "unlimited," not as zero or an error. Suggested display:

> **Credit** — Due ₹4,200.00 · Limit ₹10,000.00 · Available ₹5,800.00

or, when unlimited:

> **Credit** — Due ₹4,200.00 · No limit set

Gated by `CREDIT.VIEW` — a 403 here (with the feature on) means the
logged-in role is missing that permission; show a generic "can't check
credit" message rather than blocking checkout entirely; the server will
still enforce the limit on submit regardless.

## 3. New error: `CREDIT_LIMIT_EXCEEDED`

Returned from `POST /api/v1/sales` (not from the summary endpoint) when a
`CREDIT` payment on the sale would push the customer over their effective
limit:

```json
{
  "success": false,
  "error": {
    "code": "CREDIT_LIMIT_EXCEEDED",
    "message": "This sale would exceed the customer's credit limit",
    "details": {
      "currentBalance": "4200.00",
      "creditLimit": "10000.00",
      "attemptedChargeAmount": "6500.00"
    }
  }
}
```

422 status, same envelope shape as the existing `INSUFFICIENT_STOCK`
(`Docs/MOBILE_API_GUIDE.md` §6). Handle it like a blocking validation
error, not a generic failure toast — **re-render the due/limit display
using `error.details`** (it's authoritative and fresher than whatever the
summary call returned earlier), and require the cashier to reduce the
credit portion, collect a different payment method for the difference, or
cancel. Don't silently retry.

This can happen even after the app's own client-side check passed (another
till may have used up the limit in between) — always handle it on submit,
never skip the check just because the summary looked fine a moment ago.

## 4. New: recording a credit settlement payment

For a "Collect Payment" flow against a customer's outstanding due (separate
from a sale — e.g. the customer walks in specifically to pay down what they
owe):

```
POST /api/v1/credit/customers/24/payments
Authorization: Bearer <accessToken>
Content-Type: application/json

{ "amount": "2000.00", "paymentMethod": "CASH", "remarks": "Partial settlement, in person" }
```

```json
{
  "success": true,
  "data": {
    "id": "881",
    "amount": "2000.00",
    "paymentMethod": "CASH",
    "remarks": "Partial settlement, in person",
    "runningBalance": "2200.00",
    "createdAt": "2026-09-14T10:15:00.000Z"
  },
  "message": "Payment recorded"
}
```

`paymentMethod` here is how the *settlement* was received (`CASH`, `UPI`,
`BANK_TRANSFER`, etc.) — never `CREDIT` itself, that would be meaningless.
Gated by `CREDIT.MANAGE`, a step up from `CREDIT.VIEW` — a plain cashier
role may be able to see due amounts (`CREDIT.VIEW`) without necessarily
being allowed to record settlements (`CREDIT.MANAGE`), depending on how the
tenant sets up its roles; check for the permission in the `/auth/me`
response before showing the "Collect Payment" button.

## 5. New: transaction history (drill-down)

```
GET /api/v1/credit/customers/24/transactions?page=1&pageSize=20
```

```json
{
  "success": true,
  "data": {
    "items": [
      { "id": "881", "type": "PAYMENT", "direction": "IN", "amount": "2000.00", "paymentMethod": "CASH", "referenceType": "MANUAL", "referenceId": null, "remarks": "Partial settlement, in person", "runningBalance": "2200.00", "createdAt": "2026-09-14T10:15:00.000Z" },
      { "id": "877", "type": "SALE_CHARGE", "direction": "OUT", "amount": "1200.00", "paymentMethod": "CREDIT", "referenceType": "SALE", "referenceId": "5510", "remarks": null, "runningBalance": "4200.00", "createdAt": "2026-09-10T16:02:00.000Z" },
      { "type": "CREDIT_NOTE", "direction": "IN", "amount": "300.00", "referenceType": "SALE_RETURN", "referenceId": "212", "remarks": null, "runningBalance": "3900.00", "createdAt": "2026-09-08T09:40:00.000Z" }
    ],
    "pagination": { "page": 1, "pageSize": 20, "total": 34, "totalPages": 2 }
  }
}
```

Render this as a statement-of-account list: date, type (label
`SALE_CHARGE`→"Sale", `PAYMENT`→"Payment", `CREDIT_NOTE`→"Credit Note",
`OPENING`→"Opening Balance", `ADJUSTMENT`→"Adjustment"), signed amount
(`direction: OUT` shown as `+`, `IN` shown as `-`, from the customer's-due
point of view), and `runningBalance` as a right-aligned column so it reads
top-to-bottom like a real ledger.

## 6. New: customer-wise Credit Report (optional for this app — see below)

```
GET /api/v1/credit/report
```

```json
{
  "success": true,
  "data": {
    "items": [
      { "customerId": "24", "customerName": "Downtown Flagship Store", "totalCredit": "12400.00", "paymentsReceived": "10200.00", "pending": "2200.00", "creditLimit": "10000.00", "settlementDay": 5 }
    ],
    "pagination": { "page": 1, "pageSize": 20, "total": 6, "totalPages": 1 }
  }
}
```

Tapping a row opens the same transaction-history view as §5, scoped to
that `customerId`. **This screen is a natural fit for the Store Manager
app** (it's read-only, `CREDIT.VIEW`), but confirm with the product owner
whether it belongs on mobile at all versus staying web-only before building
it — nothing else in this doc depends on it existing in the app.

## 7. UI changes needed

- Payment-method picker: add `CREDIT`, gated on `creditEnabled` + a
  selected customer (§1).
- Checkout screen: fetch and display the summary the moment a customer is
  picked, not only after `CREDIT` is tapped (§2).
- Handle `CREDIT_LIMIT_EXCEEDED` as a distinct, actionable error state, not
  a generic failure (§3).
- New "Collect Payment" action on a customer's detail screen, gated by
  `CREDIT.MANAGE` (§4).
- New transaction-history list view, reachable from a customer's detail
  screen and (if built) from the Credit Report (§5, §6).
- Existing/opening due amount and settlement-day fields on the customer
  create/edit form, gated by `creditEnabled` — same visibility rule as
  everywhere else in this doc.

## 8. Backward compatibility

- A tenant without `CREDIT_PAYMENT` sees no change at all — no new fields,
  no new errors, no new screens. Existing `CASH/CARD/BANK_TRANSFER/UPI/CHEQUE`
  sales are completely unaffected.
- An older app build that doesn't check `enabledFeatures` and somehow still
  sends `paymentMethod: "CREDIT"` on a sale for a tenant **without** the
  feature gets `403 FEATURE_NOT_ENABLED` — same as calling any other
  feature-gated endpoint today, not a crash or a silently-accepted request.
- An older app build that ignores the new `CREDIT_LIMIT_EXCEEDED` code will
  still see a `success: false` response and a non-2xx status — it just
  won't render the friendly due/limit message; make sure generic
  error-handling doesn't swallow the response body entirely.
