# Invoice calculation logic — server-authoritative pricing

Every screen that shows money to a cashier must show a number the
**server** computed, never one the app derives from line prices,
discounts, or tax rates on-device. This doc records the current state
of that contract per flow, and the backend gap that still needs
closing.

## 1. Sale (checkout) — already server-authoritative

`SaleInvoiceScreen` (`lib/ui/screens/sales/sale_invoice_screen.dart`)
never computes the invoice breakdown itself. It builds a `QuoteInput`
from the cart/customer/coupon and asks the server for a live preview:

```
POST /pricing/quote
```

(`lib/data/repositories/pricing_repository.dart`, model in
`lib/data/models/pricing_quote.dart`). This is a read-only preview —
nothing is persisted, no coupon is redeemed — so it's safe to fire on
every cart/customer/coupon change. `QuoteController`
(`lib/state/pricing_quote_state.dart`) debounces those calls 500ms and
publishes the result as an `AsyncValue<PricingQuote?>`; the screen
renders it straight off that response.

**Bug fixed 2026-08-28:** the screen only re-requested a quote from a
`ref.listen` hook on cart *changes*. Since the cart is already
populated by the time this screen opens (built on the till screen
before navigating here), that listener never fired on initial load,
so the quote stayed `null` and the summary was stuck on "Add items to
see the invoice." forever, even with a full cart. Fixed by firing an
initial `_refreshQuote()` from `initState()`.

**Bug fixed 2026-08-28:** debounce only cancels a *pending* timer, not
a request already in flight. A slow quote fired before a coupon was
typed in could land after the coupon-bearing request was scheduled but
before it had started — legitimately carrying `coupon: null` (it was
never sent one), but the screen read that as "the server rejected the
coupon" and showed an error that then never cleared once the real,
successful response landed moments later, leaving the error message
permanently disagreeing with a total that already had the coupon
applied. Fixed by having `QuoteController` track `lastCouponCode` — the
coupon code the *published* quote was actually computed for, updated in
lockstep with `state` — so the screen only treats `coupon: null` as a
real rejection when it matches the coupon currently in the field, and
clears a stale error the instant a matching quote confirms the coupon
did apply.

**Response model completed 2026-08-28:** `PricingQuote` only parsed
`subtotal`/`lineDiscountTotal`/`grandTotal`/`coupon`, plus three fields
that were *guessed* at (`taxTotal`, `saleDiscount`,
`chargesTaxTotal`/`chargeTaxTotal`) against key names the server
doesn't actually send — see §5. The response's real `lines[]` (per-line
`unitPrice`/`lineSubtotal`/`discounts`/`lineTotal`) and `charges[]`
(per-charge `name`/`amount`/`taxAmount`) arrays were dropped entirely
even though the server always sends them. Now fully modeled
(`QuoteLine`, `QuoteLineDiscount`, `QuoteCharge`) and surfaced:
- The Items list (`_LineRow`) shows each product's server-computed
  price/discount/total once its line is in the settled quote, named by
  which Discount/coupon actually matched it — instead of only the
  locally-entered, unverified cart figures.
- The Invoice Summary itemizes every automatic Discount by name
  (`PricingQuote.discountBreakdown`) and every extra charge by name
  with its own tax, instead of one opaque "Line discounts" /
  "Extra charges" total.
- "You save" is now derived as `subtotal + charges + chargesTax -
  grandTotal` instead of summing `lineDiscountTotal + coupon.amount`,
  which double-counted a PRODUCT/CATEGORY-scope coupon: the server
  folds that coupon's reduction *into* `lineDiscountTotal` rather than
  adding it on top (see `promotion.service.ts` — `PricingQuote.
  autoDiscountTotal`/`lineCouponTotal` back this out correctly for
  both coupon scopes).

**Response model extended 2026-08-29:** the backend's `/pricing/quote`
gained real tax computation (previously it computed none at all — see
§6's sale-total fix, extended to the quote endpoint too) and started
returning per-line `tax`/`taxes`, a top-level `taxTotal`, and a
`taxInclusive` flag. None of that was in `PricingQuote` since it didn't
exist yet when the model was first built. Now parsed
(`QuoteLine.tax`/`taxes` via the new `QuoteLineTaxComponent`,
`PricingQuote.taxTotal`/`taxInclusive`) and shown as a single "Tax" row
in the Invoice Summary — additive when `taxInclusive` is `false` (the
server already summed it into `grandTotal` on top of the pre-tax
figures), shown parenthesized/muted as "Tax (included)" when `true`
(it's already folded into every line's total and into `grandTotal`;
showing it as another add-on would wrongly suggest it's charged
twice). Per-charge rows now show just `charge.amount` — the charge's
own tax is folded into that same single Tax row rather than repeated
per charge, so the same rupee isn't listed twice in the breakdown.

Also fixed in the same pass: "You save" was computed as `subtotal +
charges + chargesTax - grandTotal`, which was only correct back when
the quote had no tax term in `grandTotal` at all. Once exclusive-mode
tax started being added into `grandTotal` too, that formula started
subtracting the tax amount as if it were a savings, inflating "You
save" by the tax total. Replaced with `lineDiscountTotal +
orderCouponAmount` — derived directly from the discount/coupon fields
themselves rather than backed out of `grandTotal`, so it can't drift
regardless of how tax does or doesn't factor into the total.

Final charge still goes through `POST /sales`, which independently
recomputes and persists the real total — the quote is preview-only and
is never trusted for the actual charge amount.

## 2. Sale return — no live preview, but no local math either

`SaleReturnCreateScreen` never displays a computed total before
submit. It shows only what was sold (from the original sale) and lets
the cashier pick quantities; the refund breakdown is rendered
**after** the response comes back from:

```
POST /sale-returns
```

using the response's per-item `refundAmount` and `totalRefundAmount`
(`SaleReturn.computedRefund` in `lib/data/models/sale.dart`). This is
correct as far as it goes, but it means the cashier has no idea what
the refund will be until *after* the return is already recorded —
there's no way to preview and back out.

## 3. Sale exchange — client-side estimate only

`SaleExchangeCreateScreen` shows a running "Estimated to
collect/refund" figure while the cashier is picking return lines and
replacement products, computed entirely on-device:

```dart
double get _estimatedReturnValue {
  var total = 0.0;
  _returnQuantities.forEach((saleItemId, quantity) {
    total += quantity * (_returnUnitPrices[saleItemId] ?? 0);
  });
  return total;
}
// estimate = cartSubtotal(replacementLines) - _estimatedReturnValue
```

This uses the **original sale's line price**, not the discount-aware
refund the server would actually compute (line/sale discounts, coupon
proration, tax) — it can't, because no such API exists. The screen
already labels this correctly ("Estimate only — the server applies the
original sale's discounts and returns the exact difference.") and the
actual settlement shown to the cashier after submit comes from the
server response (`differenceAmount` / `differenceDirection` in
`SaleExchange`, via `POST /sale-exchanges`). So nothing here is
*mis*-labeled as authoritative, but the pre-submit number can visibly
disagree with the post-submit one whenever the original sale had any
discount or coupon.

## 4. Backend gap — no preview/quote endpoint for returns or exchanges

**Update 2026-08-29: this gap is closed.** `POST /sale-returns/quote`
and `POST /sale-exchanges/quote` both now exist in the backend
(`app/api/v1/sale-returns/quote/route.ts`,
`app/api/v1/sale-exchanges/quote/route.ts`,
`saleReturnService`/`saleExchangeService`'s `quote()` methods) — the
shapes below turned out to match what was actually built. The
"Client-side follow-up" section is now actionable, not blocked on
backend work: `SaleReturnCreateScreen` and `SaleExchangeCreateScreen`
can wire up to these today the same way `SaleInvoiceScreen` already
uses `POST /pricing/quote`. Left as-was below for the request/response
reference.

~~Confirmed in `lib/data/repositories/sales_repository.dart`: `sale-returns`
and `sale-exchanges` only expose `GET` (list/detail) and `POST`
(create, which persists immediately). There is no read-only preview
equivalent to `POST /pricing/quote` for either flow.~~ To let both
screens show a real, discount-aware number *before* the cashier
commits — the same guarantee checkout already has — the backend needs
two new read-only endpoints, modeled directly on `POST /pricing/quote`
(no persistence, no stock/ledger mutation, safe to call on every
quantity change):

### `POST /sale-returns/quote`

Request:
```jsonc
{
  "saleId": "…",
  "items": [
    { "saleItemId": "…", "quantity": 1 }
  ]
}
```

Response — same shape `POST /sale-returns` already returns for
`items[].refundAmount` and `totalRefundAmount`, just without creating
the record:
```jsonc
{
  "items": [
    { "saleItemId": "…", "productId": "…", "quantity": 1, "refundAmount": 449.00 }
  ],
  "totalRefundAmount": 449.00
}
```

### `POST /sale-exchanges/quote`

Request:
```jsonc
{
  "saleId": "…",
  "returnItems": [ { "saleItemId": "…", "quantity": 1 } ],
  "newItems": [ { "productId": "…", "quantity": 1, "unitPrice": 599.00 } ]
}
```

Response — same shape as the `saleReturn` / settlement fields on
`POST /sale-exchanges`'s response, just without persisting either leg:
```jsonc
{
  "returnItems": [
    { "saleItemId": "…", "productId": "…", "quantity": 1, "refundAmount": 449.00 }
  ],
  "newItems": [
    { "productId": "…", "quantity": 1, "amount": 599.00 }
  ],
  "chargesTotal": 0,
  "taxTotal": 30.00,
  "differenceAmount": 180.00,
  "differenceDirection": "CUSTOMER_OWES"
}
```

Both should apply the exact same discount/coupon/tax resolution as the
corresponding `create` endpoint, since the whole point is that the
preview and the eventual persisted result must always agree — the
create endpoints stay the source of truth, these are read-only mirrors
of the same calculation.

### Client-side follow-up once these exist

- `SaleReturnCreateScreen`: debounce a call to the new quote endpoint
  on every quantity change (same `QuoteController` debounce pattern as
  checkout) and render the real per-item/refund total instead of
  showing nothing until after submit.
- `SaleExchangeCreateScreen`: replace `_estimatedReturnValue`/the
  local `estimate` getter with the quote response, dropping the
  "Estimate only" disclaimer since the number would then be real.
- Both `PricingRepository`-style thin wrappers, following the existing
  `pricing_repository.dart` / `pricing_quote_state.dart` pattern.

Until the backend adds these, the current client behavior (return:
show nothing until after submit; exchange: show a clearly-labeled
local estimate) is the correct fallback — do not fabricate a more
precise-looking number from local math.

## 5. Request/response contract audit against the real backend

Checked `POST /pricing/quote`'s actual request/response types in the
`inventory-management` repo (`modules/pricing/schema/promotion.schema.ts`,
`modules/pricing/dto/promotion.dto.ts`,
`modules/pricing/types/promotion.types.ts`,
`modules/pricing/service/promotion.service.ts`) against what the
Flutter client sends and expects. Three real gaps found:

**a) Fields the client sends that the server silently drops.** The
request schema (`quoteSchema`) only accepts `warehouseId`, `customerId`,
`customerGroupId`, `couponCode`, `extraChargeIds` (an array of IDs) and
`lines[].{productId, categoryId, quantity, unitPrice}` — zod strips
unknown keys by default. That means:
- `PricingRepository.quote()`'s per-line `discountAmount` and the
  order-level `discountAmount`/`discountPercent` (sent whenever a
  manual discount is entered in the cart/checkout UI) are silently
  ignored — the quote preview never reflects a manually-entered
  discount at all, regardless of what the UI shows while typing it.
- `charges` is sent as `[{name, amount}]`
  (`ChargeInput.toJson()`); the server expects `extraChargeIds:
  string[]` — a list of existing `ExtraCharge` catalog entry ids to
  resolve and tax server-side, not ad-hoc name/amount pairs. This is
  currently inert in practice: `SaleInvoiceScreen` never populates
  `charges` on its `QuoteInput` (the only screen with an extra-charges
  UI, `sale_checkout_screen.dart`, isn't reachable from anywhere —
  `SaleInvoiceScreen` is the live checkout screen), so no live call
  actually exercises this mismatch today. It'll need fixing before an
  extra-charges picker is added to the live screen, though — sending
  `charges` in its current shape would just be ignored.

**b) `categoryId` is never sent per line — so CATEGORY-scoped
promotions can never preview correctly.** `discountRepository.
findApplicableForProduct` and PRODUCT/CATEGORY-coupon matching
(`promotion.service.ts`) both key off each line's `categoryId`, but the
`Product` model (`lib/data/models/catalog.dart`) doesn't parse a
category at all, so `LineInput`/`QuoteInput` never carries one. Net
effect on the live checkout screen:
- A CATEGORY-scoped automatic Discount never shows in the quote preview
  for a product in that category, even though a category-scoped
  Discount would still apply server-side when the sale is actually
  created (`POST /sales` resolves its own discounts independently of
  what the client sent to `/pricing/quote`) — so the preview
  under-states the discount, and the charge amount comes in lower than
  the preview showed.
- A CATEGORY-scoped **coupon** is worse: `promotion.service.ts` throws
  `"Coupon does not apply to any item in this order"` if it matches no
  line, which — without `categoryId` ever being sent — a
  category-scoped coupon never will from this client. Applying a
  CATEGORY-scoped coupon on a product in that category will always be
  rejected at the quote-preview step today, even though the coupon is
  perfectly valid.
- Fix requires: parsing a `categoryId` onto `Product` (need to confirm
  the products list endpoint's field name), adding it to `LineInput`/
  `QuoteLineInput`, and threading it through `CartLine.toInput()` and
  `PricingRepository.quote()`'s line payload.

**c) `POST /sales` itself doesn't accept client-supplied price or a
per-line/order discount at all.** `createSaleSchema`
(`modules/sales/schema/sale.schema.ts`) only accepts
`items[].{productId, quantity}` — the schema comment says so directly:
*"No client-supplied price or tax — price is resolved server-side from
the current price-list configuration... tax from the product's tax
rate."* There is no `discountAmount`/`discountPercent` field anywhere
on the schema, order- or line-level. That means:
- The cart's price-editing UI (`CartController.setPrice`,
  `CartLineTile`'s price field) and per-line discount UI
  (`CartController.setDiscount`) both send fields `POST /sales`
  silently ignores — the server always uses its own price-list price,
  never whatever the cashier typed.
- `LineInput.toJson()`'s `price`/`discountAmount` and
  `SalesRepository.create()`'s order-level `discountAmount`/
  `discountPercent` are exactly the "ASSUMED DISCOUNT CONTRACT" the
  comment above `SalesRepository.create()` already flags as an
  unconfirmed proposal — this audit confirms the current backend does
  **not** implement it.
- This is a bigger, separate decision (not part of this pass): either
  the backend needs `discountAmount`/`discountPercent` (line and/or
  order level) added to `createSaleSchema` and honored the same way
  `quoteSchema` would need to for §5a to matter, or the cart's
  price/discount-editing UI needs to be reconsidered for a backend that
  only does price-list pricing + coupons. Flagging here rather than
  changing checkout behavior without sign-off.

## 6. Fixed 2026-08-29 — sale totals double-counted tax under tax-inclusive pricing

Reported symptom: Sale History showed a total that looked like tax was
added *on top of* an already tax-inclusive price. Confirmed as a real
backend bug, in `inventory-management`, not a client display issue.

`TenantSetting.taxInclusivePricing` is documented
(`Docs/business-rules/taxation.md` → Tax-Inclusive vs. Tax-Exclusive
Pricing) to leave the grand total unchanged either way — inclusive
pricing only changes how much of an unchanged price gets reported as
taxable value vs. tax. `tax.service.ts`'s `computeLineTax()` honors
this correctly: under inclusive pricing it backs the tax portion *out*
of the line total purely to split it into CGST/SGST/IGST — it never
shrinks the stored `SaleItem.price`/`SaleCharge.amount`, which stay the
full, already-tax-inclusive figures.

But `sale.service.ts`'s `toSaleView()` — the function every read path
(`GET /sales`, `GET /sales/:id`, `POST /sales`, confirm/complete/
cancel/fulfillment) builds its response through — computed:

```js
const totalAmountNum = subtotalNum - discountTotalNum + totalTaxNum + chargesAmountNum;
```

unconditionally, with no branch for the inclusive case. Since
`subtotalNum`/`chargesAmountNum` already contained their own tax under
inclusive pricing, adding `totalTaxNum` on top charged it twice — a
₹118 line (18% already included) totaled as 118 + 18 = ₹136. The
identical bug existed in `sale-exchange.service.ts`'s `resolveExchange()`
(`newItemsTotal`, which drives an exchange's settlement
`differenceAmount`) — same unconditional add-on-top, same fix.

Fixed by branching on the tenant's tax-inclusive setting in both
places: skip adding the tax total when it's already baked into the
price/amount figures being summed. Since `Sale`/`SaleItem` don't
persist *which* mode a given sale was computed under (only
`TenantSetting.taxInclusivePricing`, which can change over time, and
unlike `SaleItemTax` — which snapshots its own rate specifically so it
never depends on a value that can drift later), the fix reads the
tenant's **current** setting at display time
(`taxService.resolveTaxInclusivePricing`, new). This is correct as
long as a tenant doesn't flip the setting after sales already exist
under the old value — flagged as a residual gap in a comment on
`resolveTaxInclusive` in `sale.service.ts`. If that ever becomes a
real problem, the real fix is a `Sale.taxInclusive` column snapshotted
at creation time (a schema migration), the same way `SaleItemTax`
already snapshots its rate — not attempted here since it's a bigger,
separate change and, for how new this app is, unlikely to matter yet.
