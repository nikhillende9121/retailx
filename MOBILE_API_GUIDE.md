# MOBILE_API_GUIDE.md

Audience: the Android (or any non-browser) client team building a
store-level app — most concretely, a **Store Manager** login that operates
at exactly one warehouse. This is the integration guide `API_STANDARDS.md`
doesn't cover: how to authenticate without a browser, what a
warehouse-scoped account can and can't do, and the exact endpoints such an
app needs.

---

## 1. This is a separate identity from Super Admin

There are two unrelated login surfaces in this system:

- **Tenant users** (`/api/v1/auth/**`) — what this guide covers. A person
  belongs to one tenant, one `Role`, and optionally one `Warehouse`.
- **Super Admin** (`/api/v1/super-admin/**`) — platform staff who manage
  tenants/plans/features. Not relevant to a store-level mobile app; see
  `Docs/ARCHITECTURE.md` if you need it.

Don't mix tokens between the two — they're different JWT claim shapes and
are checked by entirely separate middleware.

## 2. Authentication

Unlike the web dashboard (which stores tokens in httpOnly cookies via a
`/api/session/*` proxy meant only for the browser), a mobile app should
call the real API directly and hold the tokens itself.

### Login

```
POST /api/v1/auth/login
Content-Type: application/json

{ "tenantCode": "acme", "email": "manager@store.test", "password": "...", "deviceId": "dev-1724000000000-a1b2" }
```

`tenantCode` is required — email is only unique *within* a tenant, not
globally, so the server can't identify which tenant to check without it.
`deviceId` is sent with the login request to identify the client device.

Response:

```json
{
  "success": true,
  "data": { "accessToken": "<jwt>", "refreshToken": "<jwt>" },
  "message": "Login successful"
}
```

Both tokens come back directly in the JSON body — there's no cookie
involved on this route. Store them securely on-device (Android Keystore /
`EncryptedSharedPreferences`, not plain `SharedPreferences`).

### Using the access token

Every other call is a normal bearer-token request:

```
GET /api/v1/sales
Authorization: Bearer <accessToken>
```

- **Access token TTL: 15 minutes** (`JWT_EXPIRES_IN`, default `15m`).
- **Refresh token TTL: 7 days** (`JWT_REFRESH_EXPIRES_IN`, default `7d`).
- JWT payload is `{ sub: userId, tenantId, roleId }` — no `warehouseId`
  inside the token. Permissions and warehouse scope are both re-checked
  fresh against the database on *every* request, never trusted from the
  token — so a permission or warehouse reassignment made from the web
  dashboard takes effect on the app's very next request, no re-login
  needed.

### Refreshing

```
POST /api/v1/auth/refresh
Content-Type: application/json

{ "refreshToken": "<refreshToken>" }
```

Returns a brand-new `{ accessToken, refreshToken }` pair in the same
shape as login. Re-validates that the tenant and user are still active —
a deactivated user's refresh will fail even if the token itself hasn't
expired. Recommended pattern: attempt the request, and on a `401
UNAUTHENTICATED`, refresh once and retry; if the refresh itself fails,
force a full re-login.

### Logout

There is **no `/api/v1/auth/logout` endpoint** — tokens are stateless
JWTs with no server-side revocation list. "Logging out" on mobile just
means discarding the stored access/refresh tokens locally.

## 3. GET /api/v1/auth/me

```json
{
  "success": true,
  "data": {
    "id": "4",
    "name": "Smoke Admin",
    "email": "manager@store.test",
    "tenantId": "2",
    "role": { "id": "3", "name": "Store Manager" },
    "permissions": ["SALE.VIEW", "SALE.CREATE", "..."]
  },
  "message": "Current user retrieved"
}
```

Use `permissions` to decide which actions to show in the app (not the
authority — the server still checks every request — but it avoids
showing buttons for actions that will just 403).

**Known gap**: this response does **not** include `warehouseId` or a
warehouse name. A Store Manager app currently has no direct way to learn
its own warehouse scope from `/auth/me` — the only way to discover it
today is to call `GET /api/v1/warehouses` (see §4, which is itself
filtered to just the caller's warehouse when scoped) and see that exactly
one row comes back, or to infer it indirectly from a `403
PERMISSION_DENIED` on a mismatched warehouse. If you're building against
this API and need the scope explicit up front, ask for `/auth/me` to be
extended with `warehouseId`/`warehouseName` — it's a small addition to
`modules/auth/service/auth.service.ts`.

## 4. Warehouse scoping — what it means for this app

A user's `warehouseId` (set by a tenant admin, via `/users`) is either:

- `null` — unrestricted, acts at any of the tenant's warehouses (typical
  for a tenant admin, not a Store Manager).
- a specific warehouse — restricted to that one store. This is the
  intended shape for a Store Manager mobile login.

When restricted, violating the scope returns:

```json
{
  "success": false,
  "error": {
    "code": "PERMISSION_DENIED",
    "message": "This account is restricted to a single warehouse"
  }
}
```

HTTP status `403`. Handle this the same way as any other permission
error — it isn't retryable, and isn't a token problem (don't try to
refresh in response to it).

### Enforcement, endpoint by endpoint

| Area | Create | Get by id | List | Lifecycle actions |
|---|---|---|---|---|
| Sales | scoped (assert) | scoped (assert) | filtered to own warehouse | scoped (confirm/complete/cancel/process/pack/ship/deliver all assert) |
| Sale returns | scoped (assert) | — | filtered | — |
| Purchases | scoped (assert) | scoped (assert) | filtered | scoped (confirm/cancel/receive all assert) |
| Purchase returns | scoped (assert, against the parent purchase's warehouse) | — | — | — |
| Stock transfers | scoped (assert — **either** side of the transfer may be the caller's warehouse) | scoped (assert, either side) | filtered (either side) | scoped (ship/receive/cancel all assert, either side) |
| Inventory balance | n/a | n/a | scoped — if you pass an explicit `?warehouseId=`, it's asserted; if you omit it, the server forces the filter to your own warehouse automatically | — |
| Stock adjustments | scoped (assert) | — | (no list endpoint exists) | — |
| Warehouses | n/a | scoped (assert) | filtered to just your own row — a scoped user has no reason to even see other stores | n/a |

Stock transfers use the "either side" rule deliberately: a Store Manager
needs to both ship stock *out of* their store and receive stock *into*
it, so the check passes if **either** `fromWarehouseId` or
`toWarehouseId` matches the caller's scope — requiring both would make
transfers impossible for a scoped account.

`POST /sales/{id}/confirm`, `/complete`, `/cancel`, `/process`, `/pack`,
`/ship`, and `/deliver` all assert warehouse scope the same way create/
get/list do — a Store Manager scoped to Warehouse A gets `403
PERMISSION_DENIED` calling any of these against a sale belonging to
Warehouse B, even with a valid id.

## 5. Endpoints a Store Manager app needs

All under `/api/v1`, all require `Authorization: Bearer <accessToken>`.

**Sales**
```
GET  /sales                    SALE.VIEW
POST /sales                    SALE.CREATE
GET  /sales/{id}                SALE.VIEW
POST /sales/{id}/confirm        SALE.CONFIRM
POST /sales/{id}/complete       SALE.UPDATE   (POS shortcut: CONFIRMED -> COMPLETED)
POST /sales/{id}/cancel         SALE.UPDATE
POST /sales/{id}/process        SALE.UPDATE   (CONFIRMED -> PROCESSING)
POST /sales/{id}/pack           SALE.UPDATE   (PROCESSING -> PACKED)
POST /sales/{id}/ship           SALE.UPDATE   (PACKED -> SHIPPED)
POST /sales/{id}/deliver        SALE.UPDATE   (SHIPPED -> DELIVERED)
```

**Sale returns**
```
GET  /sale-returns              SALE_RETURN.VIEW
POST /sale-returns              SALE_RETURN.CREATE
GET  /sale-returns/{id}          SALE_RETURN.VIEW
```

**Purchases**
```
GET  /purchases                 PURCHASE.VIEW
POST /purchases                 PURCHASE.CREATE
GET  /purchases/{id}             PURCHASE.VIEW
POST /purchases/{id}/confirm     PURCHASE.UPDATE   (DRAFT -> ORDERED)
POST /purchases/{id}/cancel      PURCHASE.UPDATE   (DRAFT/ORDERED -> CANCELLED)
POST /purchases/{id}/receive     PURCHASE.RECEIVE  (ORDERED/PARTIALLY_RECEIVED -> ...)
```

**Purchase returns**
```
GET  /purchase-returns           PURCHASE_RETURN.VIEW
POST /purchase-returns           PURCHASE_RETURN.CREATE
GET  /purchase-returns/{id}       PURCHASE_RETURN.VIEW
```

**Inventory**
```
GET  /inventory/balance?warehouseId=&productId=   INVENTORY.VIEW
POST /stock-adjustments                           INVENTORY.ADJUST
```
(no list/GET endpoint exists for stock adjustments themselves)

**Stock transfers**
```
GET  /stock-transfers            STOCK_TRANSFER.VIEW
POST /stock-transfers            STOCK_TRANSFER.CREATE
GET  /stock-transfers/{id}        STOCK_TRANSFER.VIEW
POST /stock-transfers/{id}/ship    STOCK_TRANSFER.SHIP
POST /stock-transfers/{id}/receive STOCK_TRANSFER.RECEIVE
POST /stock-transfers/{id}/cancel  STOCK_TRANSFER.UPDATE
```

**Warehouses** (read-only for a Store Manager)
```
GET  /warehouses                 WAREHOUSE.VIEW
GET  /warehouses/{id}             WAREHOUSE.VIEW
```

`sales`/`purchases`/`inventory` (including stock transfers, which live
under the inventory feature) are also gated by the tenant's enabled
**features** (`SALES`, `PURCHASE`, `INVENTORY`) — feature and permission
checks are both required and are independent of each other. If a plan
doesn't include one of these features, every route under it 403s with
`FEATURE_NOT_ENABLED` regardless of the user's permissions.

## 6. Response envelope & errors

Every response, success or failure, uses the same shape:

```json
{ "success": true, "data": {}, "message": "Product created" }
```
```json
{ "success": false, "error": { "code": "VALIDATION_ERROR", "message": "...", "details": [] } }
```

List endpoints wrap `data` with pagination:

```json
{ "success": true, "data": { "items": [], "pagination": { "page": 1, "pageSize": 20, "total": 134, "totalPages": 7 } } }
```

Full current error code list:

| Code | HTTP status | Notes |
|---|---|---|
| `VALIDATION_ERROR` | 400 | Zod failure; `details` has per-field messages |
| `UNAUTHENTICATED` | 401 | Missing/invalid/expired token — try a refresh |
| `INVALID_CREDENTIALS` | 401 | Bad login — don't retry automatically |
| `FEATURE_NOT_ENABLED` | 403 | Tenant's plan doesn't include this feature |
| `PERMISSION_DENIED` | 403 | Role lacks the permission, or warehouse-scope mismatch (§4) |
| `SUBSCRIPTION_EXPIRED` | 403 | |
| `RESOURCE_NOT_FOUND` | 404 | Also returned for another tenant's/warehouse's data — never 403, to avoid confirming it exists |
| `DUPLICATE_SKU` / `DUPLICATE_BARCODE` / `DUPLICATE_CODE` / `DUPLICATE_EMAIL` | 409 | |
| `CONFLICT` | 409 | |
| `INSUFFICIENT_STOCK` | 422 | |
| `INTERNAL_ERROR` | 500 | |

Request pipeline order server-side: authenticate → resolve tenant →
check subscription → check feature → check permission → route handler
→ (for the modules above) warehouse-scope assertion. A single request
only ever fails on the *first* check it doesn't pass, so a `403` doesn't
by itself tell you whether it was a feature, permission, or warehouse
problem — read `error.code`/`error.message` to tell them apart.

## 7. Setting up a Store Manager role

A tenant admin creates the role and user from the web dashboard
(`/roles`, `/users`) or via the same endpoints directly. A realistic
minimal permission set for day-to-day store operations (no cross-store
admin capability):

```
SALE.VIEW, SALE.CREATE, SALE.CONFIRM, SALE.UPDATE
SALE_RETURN.VIEW, SALE_RETURN.CREATE
PURCHASE.VIEW, PURCHASE.CREATE, PURCHASE.UPDATE, PURCHASE.RECEIVE
PURCHASE_RETURN.VIEW, PURCHASE_RETURN.CREATE
INVENTORY.VIEW, INVENTORY.ADJUST
STOCK_TRANSFER.VIEW, STOCK_TRANSFER.CREATE, STOCK_TRANSFER.SHIP, STOCK_TRANSFER.RECEIVE, STOCK_TRANSFER.UPDATE
WAREHOUSE.VIEW
```

`SALE.UPDATE` covers every lifecycle transition except the initial
`confirm` (which is its own permission, `SALE.CONFIRM`) — there's no
separate code per transition. Deliberately excluded:
`WAREHOUSE.CREATE`/`UPDATE`/`DELETE` (store setup is a tenant-admin
action, not something a Store Manager app should be able to do), and
anything under `ROLE.*`/`USER.*` (staff management stays in the web
dashboard).

Then create the user with `warehouseId` set to that one store — either
through the `/users` page's "Store (restrict to one warehouse)" field,
or `POST /api/v1/users` with `"warehouseId": "<id>"` in the body.

## 8. Example flow

```
1. POST /api/v1/auth/login       {tenantCode, email, password} -> {accessToken, refreshToken}
2. GET  /api/v1/auth/me          (Bearer accessToken)          -> role + permissions
3. GET  /api/v1/warehouses       (Bearer accessToken)          -> exactly one row if scoped;
                                                                   today, this is the only way
                                                                   to discover which store (§3)
4. GET  /api/v1/sales?warehouseId=<own>   -> list, already filtered server-side regardless
5. POST /api/v1/sales             {warehouseId: <own>, ...}    -> 201, or 403 PERMISSION_DENIED
                                                                   if warehouseId doesn't match
6. On any 401 UNAUTHENTICATED:
   POST /api/v1/auth/refresh      {refreshToken}                -> new pair, retry step 5
   If refresh itself fails                                       -> force re-login (step 1)
```
