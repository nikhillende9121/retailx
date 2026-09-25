# Store Manager (Flutter)

A warehouse-scoped POS / inventory companion app for store staff — the mobile
counterpart to the existing web "Store" view. Built against the REST API
documented in `MOBILE_API_GUIDE.md`, `ANDROID_APP_PROMPT.md` and
`STORE_APP_GUIDE.md`. **Frontend only**: every screen is a thin UI over an
endpoint that already exists.

## Running it

```bash
flutter pub get
flutter run
```

Then on the login screen open **Server settings** and point the app at your API
(it must end at `/api/v1`). The default is `http://10.0.2.2:3000/api/v1/`, which
is a backend running on your own machine as seen from the Android emulator. The
value is saved, so you only set it once per device.

Sign in with **tenant code + email + password** — the tenant code is required
because an email is only unique within a tenant.

- `android/` is checked in and ready. The Gradle wrapper is not: Flutter injects
  it on the first build, so nothing to do.
- iOS/web folders are not included (the brief is Android). If you want them:
  `flutter create --platforms=ios,web --org com.csinc --project-name store_manager .`
- No code generation. There is no `build_runner` step — models are hand-written
  so `pub get` is the whole setup.
- Requires Flutter 3.22+ / Dart 3.4+.

## What's in it

| Area | Screens | Endpoints |
|---|---|---|
| Auth | login (tenant/email/password + server URL), auto session restore, silent refresh, local sign-out | `auth/login`, `auth/refresh`, `auth/me` |
| Sales | **till** (product grid + cart + one Charge button), sales list with status filters, detail with lifecycle buttons | `sales`, `sales/{id}`, `sales/{id}/{confirm,complete,cancel,process,pack,ship,deliver}` |
| Sale returns | list, pick a sale → pick lines → reason → server-computed refund | `sale-returns` |
| Sale exchanges | list, return lines + replacement cart + settlement method, difference banner | `sale-exchanges` |
| Purchases | list with filters, create (supplier, dates, lines), detail with confirm / receive (partial) / cancel | `purchases`, `purchases/{id}/{confirm,cancel,receive}` |
| Purchase returns | list, create against a received purchase | `purchase-returns` |
| Inventory | on-hand balance search, stock adjustment (add / write off, with reason) | `inventory/balance`, `stock-adjustments` |
| Stock transfers | list (both directions), create (send out or bring in), detail with ship / receive / cancel | `stock-transfers`, `stock-transfers/{id}/{ship,receive,cancel}` |
| Profile | store, scope, server, plan features, permissions, sign out | — |

### How the store scope is handled

The app never shows a warehouse picker: every list is filtered server-side and
every create asserts scope, so there is nothing to choose. The store name sits
in the app bar permanently.

`warehouseId` comes from `/auth/me`. Older builds of the API don't include it
(the gap `MOBILE_API_GUIDE.md` §3 calls out), so `SessionController._resolve()`
falls back to `GET /warehouses` — filtered to the caller's own row, so exactly
one row identifies the store. If an *unrestricted* account signs in (a tenant
admin, `warehouseId: null`, several warehouses visible) the app asks which store
to operate from instead of failing.

### Permission and feature gating

Nav tabs, sub-tabs, FABs and lifecycle buttons are all filtered by
`permissions` **and** `enabledFeatures` from `/auth/me`, so an action that would
certainly 403 is never offered. This is convenience, not security — the server
re-checks everything on every request, which is also why "reload permissions" in
the profile tab takes effect immediately with no re-login.

### Errors

`ApiClient` unwraps the `{ success, data, message }` / `{ success, error }`
envelope and raises a typed `AppError`. Handling per `error.code`:

| Code | Treatment |
|---|---|
| `VALIDATION_ERROR` | `error.details` mapped to inline field errors |
| `UNAUTHENTICATED` | one silent refresh + replay; if the refresh fails, tokens are dropped and the login screen explains why |
| `INVALID_CREDENTIALS` | inline on the login form, no retry |
| `FEATURE_NOT_ENABLED` | "not available on your plan" (shouldn't be reachable — nav is filtered) |
| `PERMISSION_DENIED` | "you're not allowed to do that" — never retried, never treated as a token problem |
| `RESOURCE_NOT_FOUND` | plain "not found" |
| `INSUFFICIENT_STOCK` | the server's own message, surfaced verbatim — this one is actionable |

Tokens live in `flutter_secure_storage` (Keystore / Keychain), never plain
prefs. Refreshes are single-flight, so ten parallel 401s cause one refresh.

## Layout

```
lib/
  core/          json coercion, error codes, formatters, permission + feature constants
  data/
    token_store.dart      secure token + server-URL storage
    api_client.dart       Dio, envelope unwrap, 401 refresh-and-replay
    models/               hand-written fromJson, every field defensive
    repositories/         one per API area
  state/         Riverpod providers, session controller, cart controller
  ui/
    theme.dart
    widgets/     PagedListView, AsyncView, pickers, cart panel, shared bits
    screens/     login, shell, sales/, purchases/, inventory/, transfers/, more/
```

Two widgets carry most of the plumbing: `PagedListView` (every list — pagination,
pull-to-refresh, retry, empty state) and `AsyncView` (every detail screen).

## Assumptions worth reviewing

These are the places where the guides didn't pin something down. Each is
isolated to one spot in the code.

1. **`/products`, `/customers`, `/suppliers`** — not enumerated in
   `MOBILE_API_GUIDE.md` §5, but a sale line needs a `productId` and a purchase
   needs a `supplierId`. Assumed to exist with the platform's standard list
   shape (`?page&pageSize&search`). See `CatalogRepository`. If a Store Manager
   role lacks `PRODUCT.VIEW`, the product picker automatically falls back to
   `/inventory/balance`, which is always in scope — the customer and supplier
   pickers would need those permissions granted.
2. **`POST /stock-adjustments` body** — sent as
   `{ warehouseId, productId, quantity, reason }` with a **signed** quantity
   (negative to write stock off). If the backend expects an explicit
   `type: INCREASE|DECREASE`, change `InventoryRepository.adjust()` — it is the
   only place that builds this request.
3. **`POST /purchases/{id}/receive` body** — sent as
   `{ items: [{ purchaseItemId, quantity }] }` to support partial receipts.
   Omitting `items` is treated as "receive everything outstanding".
4. **Transfer counterparty** — `GET /warehouses` is filtered to the caller's own
   row, so a scoped login usually *cannot* list the other store. When only one
   warehouse is visible the create screen asks for the other store's id; when
   several are visible it shows a dropdown. Widening `/warehouses` (or adding a
   "sibling stores" endpoint) would let the picker take over with no code change.
5. **Line price** — entered per line, because the sale endpoint has no product
   price column and price-list resolution isn't exposed to it (same as the web
   checkout). If a product happens to carry a price field, it prefills.
6. **Sale/purchase status filters for pickers** — the list endpoints take a
   single `status`, so "returnable sales" is filtered client-side after
   fetching. If the API grows a multi-status filter, move it server-side in
   `pickers.dart`.
7. **Exchange payment methods** — `CASH`, `CARD`, `UPI`, `STORE_CREDIT` in
   `core/constants.dart`; adjust to whatever the server's enum actually accepts.
8. **Field-name variants** — models accept several spellings per field
   (`saleNumber` / `number` / `code`, embedded `product` object *or* flat
   `productName`) so a naming mismatch degrades to a sensible label instead of a
   crash. Once the real payloads are confirmed, `core/json.dart`'s `firstOf`
   lists can be trimmed.

## Deliberately not here

No product / category / brand / tax-rate management, no roles or users, no
pricing or coupon administration, no Super Admin anything, no warehouse
create/edit/delete. Those are tenant-admin concerns and stay in the web
dashboard. There is no cash-drawer session or shift open/close either — a sale
from this app is a plain `channel: "POS"` sale, exactly like one made from the
dashboard.
#   R e t a i l  
 #   r e t a i l x  
 