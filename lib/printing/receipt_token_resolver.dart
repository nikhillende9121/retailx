import '../core/formatters.dart';
import '../data/models/sale.dart';
import '../data/models/catalog.dart';
import '../data/models/tenant.dart';

/// Builds the token map the receipt schema's `{{placeholders}}` resolve
/// against, and performs the actual substitution.
///
/// The token set is **exactly** the snake_case list from the guide (§1):
/// ```
/// {{store_name}} {{address}} {{invoice_no}} {{date}} {{time}}
/// {{cashier}} {{subtotal}} {{tax}} {{discount}} {{total}}
/// ```
/// Any other spelling silently resolves to `""`, matching the Android app's
/// own behavior (an unresolved token is replaced with an empty string, not
/// left visible and not an error).
class ReceiptTokenResolver {
  ReceiptTokenResolver._();

  /// Builds the flat key→value map from the sale's data.
  static Map<String, String> buildTokens({
    required Sale sale,
    required Warehouse shop,
    TenantProfile? tenant,
    String? cashierName,
  }) {
    final date = parseDate(sale.saleDate ?? sale.createdAt);
    final totalTax = sale.itemsTaxTotal + sale.chargesTaxTotal;

    return {
      'store_name': shop.name,
      'address': (shop.address ?? '').trim(),
      'invoice_no': sale.number ?? '#${sale.id}',
      'date': date != null ? prettyDate(date.toIso8601String()) : '—',
      'time': date != null ? clock(date.toLocal()) : '',
      'cashier': (cashierName ?? '').isNotEmpty ? cashierName! : '—',
      // receiptAmount, not money() — this map feeds the ESC/POS path too,
      // and money()'s ₹ glyph prints as a blank/garbage box on a real
      // thermal printer. See receiptAmount's doc comment.
      'subtotal': receiptAmount(sale.itemsSubtotal),
      'tax': receiptAmount(totalTax),
      'discount': receiptAmount(sale.discountTotal),
      'total': receiptAmount(sale.computedTotal),
    };
  }

  /// Replaces every `{{key}}` in [template] with the matching value from
  /// [tokens]. Unknown keys become `""` — never left visible.
  static String resolve(String template, Map<String, String> tokens) {
    return template.replaceAllMapped(
      RegExp(r'\{\{(\w+)\}\}'),
      (match) => tokens[match.group(1)] ?? '',
    );
  }
}
