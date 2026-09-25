# STORE_APP_GUIDE.md

## What this is

A **simplified, POS-styled web frontend** for warehouse-scoped users,
living alongside the existing admin dashboard rather than inside it —
built in this same Next.js application, reusing the same login, session,
and APIs as the dashboard. Originally proposed as a "web replica of the
Android Store Manager app"; now implemented, including a terminal-style
shell and a checkout-style Sales flow.

## Why

`Docs/MOBILE_API_GUIDE.md` documents a full REST API surface built for an
Android **Store Manager** app — a login restricted to one warehouse
(`User.warehouseId`) that lists/creates/progresses Sales, Sale Returns,
Purchases, Purchase Returns, Inventory, and Stock Transfers, all scoped to
that one store. That API is live and working today.

A warehouse-scoped user *can* technically log into the admin dashboard
(`/(dashboard)/**`) — nav items are filtered by permission, so a narrow
Store Manager role already only sees Sales/Purchases/Inventory/Stock
Transfers there — but that UI is built for tenant admins: dense paginated
tables, multi-field CRUD forms, category/brand/tax-rate pickers, etc. It
doesn't feel like the task-focused, few-taps flow a mobile app gives a
cashier or store lead, and it exposes far more surface area than a
store-level user actually needs.

The goal: give that same warehouse-scoped user a **simpler, purpose-built
web experience** — reusing the exact same login, session, and APIs, just
a different frontend.

## Explicitly out of scope

- **Real POS Terminal / Cash Session backend** (`Docs/business-rules/pos.md`).
  `Terminal` and `CashSession` still exist as Prisma models with zero
  backing service/controller/routes — nothing here changes that. The
  shell and checkout screen below borrow the *visual language* of a POS
  terminal (icon nav rail, live clock, product-grid checkout) but there
  is no cash-drawer session, no shift open/close, no cash reconciliation.
  A Sale created from `/store/sales` is a plain `channel: "POS"` sale,
  identical to one created from the dashboard — confirmed with the user
  as visual-only, not a cash-session feature.
- Anything not in the Store Manager's permission set per
  `MOBILE_API_GUIDE.md` §7: no product/category/brand/tax-rate catalog
  management, no roles/users, no Super Admin anything, no warehouse
  create/update/delete (store setup stays a tenant-admin action).
  **Not** out of scope, despite an earlier draft of this doc lumping it
  in here: *applying* a coupon code or an extra charge at checkout — the
  Sales and Sale Exchange create flows both do this today (see "What
  'simplified'/'checkout-style' concretely means" below). Only *managing*
  the underlying Discount/Coupon/Price List/Extra Charge catalog entries
  stays a tenant-admin action.
- No new backend endpoints for any area below except Sale Exchanges
  (added after this doc's original scope — see
  `modules/sales/service/sale-exchange.service.ts` and
  `sale-exchange.controller.ts`; there is no `Docs/business-rules/
  sale-exchange.md`, despite an earlier draft of this doc citing one).
  Every other capability is scoped/filtered server-side exactly as
  `MOBILE_API_GUIDE.md` describes; this remains a frontend-only effort
  consuming those same routes through the existing
  `apiClient`/`/api/proxy/v1/**` cookie session, same as the admin
  dashboard.

## Scope — what the store area covers

One simplified web page/flow per area:

| Area | Capability | Backing endpoints |
|---|---|---|
| Sales | list (own store), **checkout-style create** (product grid + cart), view detail, confirm/complete/cancel/process/pack/ship/deliver | `/sales`, `/sales/{id}`, `/sales/{id}/{action}` |
| Sale returns | list, create — **no detail/view page** (see below) | `/sale-returns` |
| Sale exchanges | list, create (return item(s) + sell replacement item(s) + settle the difference, one transaction) — **no detail/view page** | `/sale-exchanges` |
| Purchases | list, create, view, confirm/cancel/receive | `/purchases`, `/purchases/{id}`, `/purchases/{id}/{action}` |
| Purchase returns | list, create — **no detail/view page** | `/purchase-returns` |
| Inventory | balance for own store, **read-only** | `/inventory/balance` |
| Stock adjustments | create a manual adjustment — a separate page/nav item from Inventory, not the same screen | `/stock-adjustments` |
| Stock transfers | list (either side of own store), create, ship, receive, cancel | `/stock-transfers`, `/stock-transfers/{id}`, `/stock-transfers/{id}/{action}` |

There is **no Warehouses page under `/store`** — an earlier draft of this
doc claimed a read-only warehouses view; it was never built (no route, no
nav item). `GET /warehouses`/`/warehouses/{id}` exist on the API and are
used internally (e.g. resolving the caller's own store name), just not as
a page a user navigates to directly.

Every one of these is warehouse-scoped/filtered server-side
(`shared/utils/assert-warehouse-access.ts`) — the frontend doesn't add
any scoping logic of its own, it just doesn't show a warehouse picker
where the admin dashboard does, since there's only ever one possible
value.

Sales and Purchases got the full checkout/cart-style treatment described
below, each with its own detail page. Sale Returns, Sale Exchanges and
Purchase Returns are list + create-dialog only — the backing `{id}`
endpoints exist and are used internally, but there's no page to drill
into a past record and see it again. Inventory and Stock Transfers are
simplified list (+ create-dialog, for transfers) pages — same building
blocks as the dashboard's, just warehouse-implicit — not (yet) rebuilt as
tap-first flows. That's a real gap, not an oversight; see "Possible
follow-ups" below.

## Where it lives

```
app/(store)/store/layout.tsx              — StoreSidebar + StoreTopbar shell
app/(store)/store/page.tsx                 — redirect("/store/sales")
app/(store)/store/sales/page.tsx           — checkout screen (grid + cart)
app/(store)/store/sales/[id]/page.tsx
app/(store)/store/sale-returns/page.tsx    — list + create dialog, no [id] page
app/(store)/store/sale-exchanges/page.tsx  — list + create dialog, no [id] page
app/(store)/store/purchases/page.tsx
app/(store)/store/purchases/[id]/page.tsx
app/(store)/store/purchase-returns/page.tsx — list + create dialog, no [id] page
app/(store)/store/inventory/page.tsx       — balance, read-only
app/(store)/store/adjustments/page.tsx     — create a stock adjustment
app/(store)/store/stock-transfers/page.tsx
app/(store)/store/stock-transfers/[id]/page.tsx
```

Same Next.js app, same build, same deploy — a second route group sitting
next to `app/(dashboard)/**`. Reuses the same auth: `/login`, the same
httpOnly session cookies, the same `/api/proxy/v1/**` translation layer,
the same `useAuth()`/`apiClient`. No second login, no second token type.

**Shell components** (`components/layout/store-sidebar.tsx`,
`components/layout/store-topbar.tsx`) are distinct from the dashboard's
(`sidebar.tsx`, `header.tsx`) — a Material-style icon nav rail instead of
a text sidebar, and a top bar leading with the store name and a live
clock instead of a bare account menu. The dashboard's own shell is
untouched.

## How a user gets to `/store` vs `/(dashboard)`

Resolved (this was an open question in the original proposal): a new
permission, **`STORE.ACCESS`**, toggled per role from the Roles screen
like any other permission. On login (`app/login/page.tsx`), a user whose
role holds `STORE.ACCESS` is sent straight to `/store` instead of the
dashboard — unless an explicit `?next=` deep link is present, which
always wins.

`STORE.ACCESS` is deliberately **excluded** from the "grant every catalog
permission" bootstrap that a fresh tenant's Admin role and the demo Admin
role both receive (`shared/constants/permissions.ts`) — it's a
login-redirect signal, not a capability, so an Admin doesn't silently
start landing on `/store` just because they hold every other permission.
It must be turned on explicitly for whichever role should live there.

The original manual links still exist alongside the new auto-redirect —
`components/layout/sidebar.tsx`'s "Switch to Store view" (dashboard →
store) and the nav rail's own Dashboard icon (store → dashboard) — so a
user who holds both `STORE.ACCESS` and dashboard permissions can still
move between the two in one session; auto-redirect just decides where
they land right after login, not a hard wall between the two areas.

## What "simplified"/"checkout-style" concretely means

- Lists default-filtered to the caller's own warehouse with no picker to
  change it (there's nothing else to pick).
- **Sales create flow is a real checkout screen**, not a form: a
  searchable product grid (tap a tile to add to cart), a cart panel with
  quantity steppers and a per-line price shown read-only (price is
  resolved server-side, not client-editable — `resolveItemPrice` in
  `modules/sales/service/sale.service.ts`), an optional coupon-code field
  and a list of extra-charge checkboxes, and a single "Charge <amount>"
  action — same `POST /sales` payload/validation as the dashboard
  underneath, just a tap-first input surface instead of a dynamic form
  array. The coupon and extra charges aren't cosmetic: they run through
  `promotionService.quote()`/`applyQuoteToSale()`
  (`modules/pricing/service/promotion.service.ts`) the same way every
  other consumer of that engine does, so the discount/coupon redemption
  and charge totals are computed and applied server-side, not just
  echoed back. Sale Exchange's replacement-items step has the same
  coupon-code and extra-charge fields, for the same reason.
- Bigger touch targets, fewer visible columns per list, action buttons
  for the lifecycle verbs (Confirm/Ship/Receive/etc.) front-and-center
  rather than tucked into a row-actions menu.
- No relation pickers the Store Manager permission set has no reason to
  touch (no category/brand/tax-rate management surfaces here at all —
  those are selected *from* existing catalog data when building a sale/
  purchase line, never created/edited from this area).

## Possible follow-ups (not yet built)

- Extend the checkout/cart treatment to Sale Returns and Sale Exchanges'
  item-picking step (today they're still list + dialog, just
  warehouse-implicit).
- A detail/view page for Sale Returns, Sale Exchanges and Purchase
  Returns. Each has a working `GET .../{id}` endpoint already — Sales,
  Purchases and Stock Transfers all drill into one — but these three
  don't have a page to land on, so a past record can't be revisited once
  it scrolls off the list.
- A read-only warehouse info view under `/store`, if a store user ever
  needs to double-check their own store's details without leaving the
  area (the mobile app's API surface already supports `GET /warehouses`
  for this; the store web frontend just doesn't have a page for it).
- A real Terminal/Cash Session backend, if the business actually needs
  shift-based cash reconciliation — see "Explicitly out of scope" above.
