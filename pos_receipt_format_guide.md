# POS Receipt Format — Backend & Portal Guide

This is the backend/portal-side counterpart to the Android app's own receipt-format
development guide. It documents:

1. The exact schema contract a Super Admin authors (Section 1) — section types, every
   field each one takes, text sizing, spacing, alignment.
2. The exact API shape this backend returns to the Android app (Section 2), verified
   field-by-field against the Android guide, with every deliberate deviation called out.
3. Where this lives in code (Section 4), for whoever touches this next.

If you're implementing or reviewing the Android side, Section 2 is the part that
matters — it's the literal wire contract, not a paraphrase.

---

## 1. The schema contract

A receipt format's `schema` column is `{ "sections": [...] }` — an ordered list of
sections, each rendered top to bottom. The app tolerates unknown `type`s (skips them,
never crashes), so new section types can ship here before the app is updated — but the
fields *within* a known type must match exactly, since the app reads them by literal key.

**The main content field is always `value`, never `content`.** This is the single most
common mistake when hand-authoring a schema — `text`, `image`, `barcode`, and `qr` all
use `value`; only `keyvalue` additionally has `key`.

| type       | fields                                                                        | notes |
|------------|--------------------------------------------------------------------------------|-------|
| `text`     | `value` (string, may contain `{{tokens}}`), `align` (`left`\|`center`\|`right`), `bold` (boolean), `size` (`xs`\|`small`\|`normal`\|`large`) | one line of text |
| `keyvalue` | `key` (string), `value` (string, may contain `{{tokens}}`), `bold` (boolean) | label on the left, value on the right, same line |
| `divider`  | *(no fields)*                                                                 | full-width separator line |
| `items`    | `columns` (array — any subset/order of `"name"`, `"qty"`, `"price"`, `"total"`; see the custom-column warning below), `headers` (object, column key → custom label, e.g. `{ "name": "Product" }`), `totals` (array of `{ label, value, bold? }` — Subtotal/Tax/Total rows merged into this table as a footer; see the warning below) | renders the sale's line items **as a table, with a header row** — `columns` controls which columns show and their order, `headers` controls each one's label |
| `image`    | `value` (an image URL), `align` (`left`\|`center`\|`right`)                  | logo — the printer needs a monochrome bitmap, the URL is fetched and converted on-device |
| `barcode`  | `value` (string, may contain `{{tokens}}`)                                   | symbology defaults to `code128` on the app side — see the warning below |
| `qr`       | `value` (string, may contain `{{tokens}}`)                                   | |
| `spacer`   | `lines` (integer)                                                             | blank vertical space, that many text-lines tall |
| `terms`    | `value` (string, `\n`-separated lines, may contain `{{tokens}}`), `align`, `size` (defaults to `xs`) | a small-print terms & conditions block — see the warning below |
| `row`      | `sections` (array of section objects, any type, even a nested `row`) | lays its children out **side by side** instead of stacked — see the warning below |

⚠️ **`terms` is a portal-only addition — it isn't in the original Android guide's
section-type list at all.** It previews here exactly like a small multi-line `text`
block, but per the app's own forward-compatible design, an unrecognized `type` is
skipped silently, not rendered with some default styling. That means a `terms` section
prints **nothing** on a real device until the Android renderer adds a matching case.
Until then, an equivalent way to get terms & conditions onto an actual printed receipt
today is a plain `text` section with `size: "xs"` and `\n` for line breaks — same visual
result, but it works right now because `text` already has device support.

⚠️ **`row` is a portal-only addition too, with a sharper failure mode than the others.**
The Android guide's renderer (Section 6.2's `renderReceipt`) is one straight top-to-bottom
loop over `sections` — there's no concept anywhere of laying two sections out next to
each other. A `row` previews here as a real side-by-side layout (each child gets an equal
share of the width, or a custom share via that child's own `width`, a relative number), but
on a real device, `row` is just an unrecognized `type` like any other — which means **every
section nested inside it is skipped too, not stacked as a fallback**. Don't put anything
inside a `row` that must actually appear on a printed receipt until the Android renderer
adds support for it (and decides what its own fallback behavior should be — stacked,
first-child-only, or something else).

**Text sizing** (`size` on a `text` section): `xs` / `small` / `normal` (default) / `large`.
There's no numeric point size — the app maps these buckets to its own font scale so
a receipt stays legible at both 58mm and 80mm.

⚠️ **`xs` is a portal-only addition.** The original Android guide's own field table only
defines three buckets (`small`/`normal`/`large`). `xs` previews correctly in the Super
Admin UI, but won't print any smaller than whatever the app's `small` bucket maps to
until the Android renderer adds a matching `xs` case to its own size switch. Flag this to
the Android team before relying on it for anything that needs to be genuinely tiny (e.g.
dense multi-column tables on a wide sheet).

**Spacing**: there's no generic margin/padding field on any section — vertical spacing is
entirely `divider` (a visible rule) and `spacer` (blank space, sized in `lines`) between
sections. Horizontal spacing on a `keyvalue` row is automatic (label left, value right,
filled to the paper width); a `text` section's `align` is its only horizontal control.

**Paper width isn't limited to narrow thermal rolls.** `paperWidth` is a plain integer
(mm) with no enforced range — a wide/landscape format (e.g. `210` for an A4-style sheet)
is just as valid as `58`/`80`, and the Super Admin UI's live preview renders it at true
physical scale (with a cm ruler on both edges) rather than squeezing everything into a
fixed-size box, so what you see is close to what actually prints.

⚠️ **A custom `items` column previews, but doesn't print, until the app supports it.**
`name`/`qty`/`price`/`total` are the only fields the Android app's on-device line-item
data actually carries per item (see its own transaction-data example: each item is just
`{ name, qty, price, total }`). The Super Admin UI's `columns` array will accept any key
you put in it — e.g. `"sku"` — and the live preview shows it with placeholder "— sample —"
values so you can see the layout, but on a real device that column renders blank, since
there's no `sku` value in the app's item data to fill it with. Getting a genuinely new
column onto a real receipt requires the Android app's line-item data model to be
extended first — this backend and portal have no part to play in that (the `schema` JSON
only says how to lay out data the app already has).

⚠️ **`items.totals` (Subtotal/Tax/Total merged into the table) is portal-preview-only —
the default template uses it, by explicit choice, for a better invoice-style look while
authoring, but it won't print on a real device yet.** The Android guide's `items` section
is just a table of line items — it has no footer concept at all. `totals` lets you author
Subtotal/Discount/Tax/Total (or anything else) as extra rows inside the same bordered
table, and the Super Admin UI's live preview renders it that way, but nothing in `totals`
reaches a real receipt until the app's items renderer grows a matching footer case. **If
you need these values to actually print today**, replace `totals` with separate
`keyvalue` sections right after the `items` section instead — e.g.
`{ "type": "keyvalue", "key": "Subtotal", "value": "{{subtotal}}" }` — since `keyvalue`
is a real, currently-supported section type. Both approaches use the same tokens
(`{{subtotal}}`/`{{discount}}`/`{{tax}}`/`{{total}}`); only where they're placed differs.

⚠️ **Barcode symbology field is ambiguous in the original Android spec.** Its own field
table lists a `type` property for the barcode's symbology (e.g. `code128`) — but that
collides with the section's own dispatch key, which is *also* called `type` and is
already `"barcode"` for this section. The Android reference implementation in that spec
reads `s['type']` again inside the `barcode` case, which would just read back
`"barcode"`, not a real symbology. Until the Android side confirms/fixes this (most
likely by renaming the field to something like `format`), don't rely on setting barcode
symbology from the schema — every barcode renders as the app's hardcoded default
(`code128`) regardless of what's authored here.

### Example (what `DEFAULT_SCHEMA` in the Super Admin UI pre-fills)

```json
{
  "sections": [
    { "type": "text", "value": "{{store_name}}", "align": "center", "bold": true, "size": "large" },
    { "type": "text", "value": "{{address}}", "align": "center", "size": "small" },
    { "type": "divider" },
    { "type": "keyvalue", "key": "Invoice", "value": "{{invoice_no}}" },
    { "type": "keyvalue", "key": "Date", "value": "{{date}} {{time}}" },
    { "type": "keyvalue", "key": "Cashier", "value": "{{cashier}}" },
    { "type": "divider" },
    {
      "type": "items",
      "columns": ["name", "qty", "price", "total"],
      "headers": { "name": "Item", "qty": "Qty", "price": "Price", "total": "Total" },
      "totals": [
        { "label": "Subtotal", "value": "{{subtotal}}" },
        { "label": "Discount", "value": "{{discount}}" },
        { "label": "Tax", "value": "{{tax}}" },
        { "label": "TOTAL", "value": "{{total}}", "bold": true }
      ]
    },
    { "type": "spacer", "lines": 1 },
    { "type": "qr", "value": "{{invoice_no}}" },
    { "type": "spacer", "lines": 1 },
    { "type": "terms", "value": "All sales are final.\nGoods once sold will not be exchanged or refunded." },
    { "type": "text", "value": "Thank you!", "align": "center" }
  ]
}
```

### Allowed placeholder tokens

The Android app builds its on-device data map with **exactly these snake_case keys** —
any other spelling (e.g. `{{storeName}}`, `{{invoiceNumber}}`) silently renders as an
empty string on the device, since an unresolved token is replaced with `""`, not left
visible and not an error. This is the #1 way a hand-authored schema "looks fine" in the
portal but prints blank fields on a real device — always author against this exact list:

```
{{store_name}} {{address}} {{invoice_no}} {{date}} {{time}}
{{cashier}} {{subtotal}} {{tax}} {{discount}} {{total}}
```

(`{{items}}` also exists as a data key, but it's an array consumed by the `items`
section type, not a scalar token you'd drop into a `text`/`keyvalue` value.)

Validation is deliberately **loose** on the backend (see
`modules/receipt-format/schema/receipt-format.schema.ts`) — only `{ sections: [{ type:
string, ...anything }] }` is enforced. Field names above aren't checked by a Zod enum;
getting them right is on whoever authors the schema. The Super Admin UI's live preview
(and its "Show section type reference" panel) exists specifically to catch mistakes
before they reach a device.

---

## 2. Backend ⇄ Android app contract

This is what this backend's `/pos/{posId}/receipt-format` endpoints actually return —
verified against the Android app's own guide, with every place this implementation
deviates from that guide's literal examples called out and justified.

### 2.1 `GET /pos/{posId}/receipt-format`

Auth: `Authorization: Bearer <token>` (same POS/user token as every other
`/api/v1/**` route), permission `SALE.VIEW`.

```json
{
  "success": true,
  "message": "Receipt format retrieved",
  "data": {
    "formatId": "12",
    "name": "Default Store Receipt",
    "version": 7,
    "paperWidth": 58,
    "schema": { "sections": [ ... ] }
  }
}
```

Resolution precedence (most specific wins): **POS device → store → tenant → global
default**. `404 RESOURCE_NOT_FOUND` if nothing resolves at any level (no assignment
anywhere and no format has `isDefault: true`) — same as "no format resolved" in the
Android guide; the app should fall back to its bundled default schema in that case.

### 2.2 `GET /pos/{posId}/receipt-format/version`

Same auth/permission. Lightweight — call on startup, only fetch 2.1's full payload when
this differs from the cached version.

```json
{ "success": true, "message": "Receipt format version retrieved", "data": { "version": 7 } }
```

### 2.3 Two deliberate deviations from the Android guide's literal examples

The Android guide's own JSON examples show a flat, un-enveloped response
(`{ "formatId": 12, ... }` directly, no wrapper) with `formatId` as a bare number. This
implementation does **not** match that literally — on purpose:

1. **The `{success, data, message}` envelope is kept**, not flattened. Every other
   endpoint this same Android app already calls (sales, products, everything in
   `Docs/MOBILE_API_GUIDE.md`) uses this envelope — the app's HTTP layer already expects
   to unwrap it. Special-casing just this one endpoint to skip the envelope would be a
   worse mismatch than what it's trying to avoid.
2. **`formatId` is a JSON string (`"12"`), not a bare number.** Every other id this app's
   mobile API returns is a string (see `Docs/MOBILE_API_GUIDE.md` — `"id": "4"`, not
   `4`) because ids are 64-bit `BigInt` server-side and JS/JSON numbers above 2^53 lose
   precision. Matching that existing, already-shipped convention beats matching one
   example in a generic guide.

If the Android team specifically needs a bare int for `formatId`, say so and this can be
special-cased — but as of this writing, no other part of this app's mobile API does that,
so this endpoint doesn't either.

### 2.4 What did match exactly (no changes needed)

- `paperWidth`, `version`, and `schema: { sections: [...] }` — same shape, same names.
- Resolution precedence (POS → store → tenant → default) and the 404-on-nothing-resolved
  behavior.
- The version-check endpoint's minimal `{ version }` payload (inside `data`).

---

## 3. Portal-side endpoints (Super Admin only — the Android app never calls these)

Base path `/api/v1/super-admin/receipt-formats`, auth via `withSuperAdminAuth` (platform
staff, not a tenant user).

```
GET    /receipt-formats                list every format + its current assignments
POST   /receipt-formats                create — { name, paperWidth, schema, isDefault }
GET    /receipt-formats/{id}           get one
PUT    /receipt-formats/{id}           full replace — bumps `version` by 1
DELETE /receipt-formats/{id}           soft delete — unassigns it from everything it was assigned to
POST   /receipt-formats/{id}/assign    body: { tenantId? } | { warehouseId? } | { terminalId? } — exactly one
POST   /receipt-formats/{id}/clone     body: { name } — duplicates schema/paperWidth, never isDefault or assignments
```

One deliberate simplification vs. the Android guide's own sketch of this endpoint: that
guide's `/assign` takes **arrays** (`{ tenantIds?, storeIds?, posIds? }`) for bulk
assignment in one call. This implementation takes exactly **one** scalar target per call
(`tenantId` *or* `warehouseId` *or* `terminalId`) instead — simpler to reason about and
to build a picker UI for; bulk-assigning to N tenants is N calls. Since the Android app
never calls this endpoint, this doesn't affect the device contract — only the Super Admin
UI, which already calls it this way.

`warehouseId`/`terminalId` are this app's own vocabulary for what the Android guide calls
"store" and "POS device" respectively (see `prisma/schema.prisma`'s `Warehouse` and
`Terminal` models).

POS-device-level (`terminalId`) assignment has no picker in the Super Admin UI — `Terminal`
has no listing/search screen anywhere in the portal yet, so there's nothing to pick from.
It's fully functional via a direct API call in the meantime.

---

## 4. Where this lives

- `prisma/schema.prisma` — `ReceiptFormat`, `ReceiptFormatAssignment` models.
- `modules/receipt-format/` — repository, service (`resolveForTerminal` is the
  precedence-resolution logic), schema, dto, types, controllers, tests.
- `app/api/v1/pos/[posId]/receipt-format/**` — the Android-facing routes (Section 2).
- `app/api/v1/super-admin/receipt-formats/**` — the authoring routes (Section 3).
- `app/super-admin/(dashboard)/receipt-formats/` — the authoring UI:
  - `page.tsx` — the list, plus the Clone/Assign/Delete dialogs (small enough to stay
    as dialogs).
  - `new/page.tsx` / `[id]/page.tsx` — full-page create/edit forms, not modals — the
    schema JSON textarea + live preview need more room than a dialog comfortably gives.
  - `receipt-format-form.tsx` — the shared form: fields, the live preview (rendered
    against sample data using the exact field names and tokens from Section 1, with a
    cm ruler and true-physical-scale sizing), and a "Download PDF" button
    (`window.print()` into a fixed one-A4-page layout — content is scaled down, never
    up, only when it would otherwise span multiple pages).
  - `assign-format-dialog.tsx` — the tenant/store assignment dialog, shared between
    the list page and the edit page's own "Assign to tenant / store" button.
