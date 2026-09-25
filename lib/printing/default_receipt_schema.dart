import '../data/models/receipt_format.dart';

/// The bundled default receipt schema — used when the backend has no format
/// assigned for this POS device / store / tenant.
///
/// Matches the `DEFAULT_SCHEMA` from `pos_receipt_format_guide.md` §1, with
/// one deliberate change: Subtotal/Discount/Tax/Total are expressed as
/// `keyvalue` sections instead of `items.totals`, because `items.totals` is
/// portal-preview-only and won't print on a real device until the Android
/// renderer adds a matching footer case (guide §1 warning).
///
/// `terms` is also deliberately rendered here — this renderer supports it
/// natively (as a small-print text block), even though the original Android
/// guide's section-type list doesn't include it.
const Map<String, dynamic> kDefaultReceiptSchemaJson = {
  'sections': [
    {
      'type': 'text',
      'value': '{{store_name}}',
      'align': 'center',
      'bold': true,
      'size': 'large',
    },
    {
      'type': 'text',
      'value': '{{address}}',
      'align': 'center',
      'size': 'small',
    },
    {'type': 'divider'},
    {'type': 'keyvalue', 'key': 'Invoice', 'value': '{{invoice_no}}'},
    {'type': 'keyvalue', 'key': 'Date', 'value': '{{date}} {{time}}'},
    {'type': 'keyvalue', 'key': 'Cashier', 'value': '{{cashier}}'},
    {'type': 'divider'},
    {
      'type': 'items',
      'columns': ['name', 'qty', 'price', 'total'],
      'headers': {
        'name': 'Item',
        'qty': 'Qty',
        'price': 'Price',
        'total': 'Total',
      },
    },
    {'type': 'divider'},
    {'type': 'keyvalue', 'key': 'Subtotal', 'value': '{{subtotal}}'},
    {'type': 'keyvalue', 'key': 'Discount', 'value': '{{discount}}'},
    {'type': 'keyvalue', 'key': 'Tax', 'value': '{{tax}}'},
    {
      'type': 'keyvalue',
      'key': 'TOTAL',
      'value': '{{total}}',
      'bold': true,
    },
    {'type': 'spacer', 'lines': 1},
    {'type': 'qr', 'value': '{{invoice_no}}'},
    {'type': 'spacer', 'lines': 1},
    {
      'type': 'text',
      'value':
          'All sales are final.\nGoods once sold will not be exchanged or refunded.',
      'align': 'center',
      'size': 'xs',
    },
    {'type': 'text', 'value': 'Thank you!', 'align': 'center'},
  ],
};

/// Pre-parsed default format, ready to use.
ReceiptFormat get kDefaultReceiptFormat => ReceiptFormat.fromJson({
      'formatId': 'default',
      'name': 'Default Receipt',
      'version': 0,
      'paperWidth': 58,
      'schema': kDefaultReceiptSchemaJson,
    });
