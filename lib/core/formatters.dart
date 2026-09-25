import 'package:intl/intl.dart';

final NumberFormat _money = NumberFormat.currency(
  locale: 'en_IN',
  symbol: '₹',
  decimalDigits: 2,
);

final DateFormat _apiDate = DateFormat('yyyy-MM-dd');
final DateFormat _prettyDate = DateFormat('d MMM yyyy');
final DateFormat _prettyDateTime = DateFormat('d MMM yyyy, h:mm a');
final DateFormat _clock = DateFormat('h:mm a');

/// `1234.5` -> `₹1,234.50`. On-screen UI only — never use this for text that
/// reaches a thermal printer (see [receiptAmount]).
String money(num? value) => _money.format(value ?? 0);

/// `1234.5` -> `Rs. 1234.50`, `-1234.5` -> `-Rs. 1234.50`.
///
/// The ₹ glyph has no representation in the Latin-1-ish codec ESC/POS
/// generators talk to a thermal printer with, and cheap printer modules
/// don't carry a code page that includes it either — it prints as blank or
/// garbage. "Rs." is what every till receipt in this market already uses
/// for the same reason. Use this (not [money]) for every amount that ends
/// up as receipt text — that includes the `{{subtotal}}`/`{{tax}}`/
/// `{{discount}}`/`{{total}}` tokens `ReceiptTokenResolver` builds, since
/// those feed the ESC/POS path as well as the PDF one.
String receiptAmount(num? value) {
  final v = (value ?? 0).toDouble();
  final prefix = v < 0 ? '-Rs. ' : 'Rs. ';
  return '$prefix${v.abs().toStringAsFixed(2)}';
}

/// `1234.5` -> `1234.50` — no symbol, no thousands separator.
///
/// For per-item figures on a receipt (a schema's `items` table cells): a
/// currency prefix on every single row is clutter a till receipt doesn't
/// carry — [receiptAmount]'s "Rs." is reserved for the one line that needs
/// it (a bold grand total). Same reasoning as [receiptAmount] for why this
/// can't be [money]: the PDF renderer's default font is one of the base-14
/// PDF fonts (Helvetica), which predates ₹ same as a thermal printer's code
/// page does — money() risks a missing-glyph box there too, not just on
/// ESC/POS.
String receiptPlainAmount(num? value) => (value ?? 0).toStringAsFixed(2);

/// Quantities are conceptually integers at a till but the API models them as
/// decimals; don't show `2.0` where `2` is meant.
String qty(num? value) {
  final v = value ?? 0;
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v.toString();
}

/// The `saleDate` / `purchaseDate` wire format.
String apiDate(DateTime date) => _apiDate.format(date);

DateTime? parseDate(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  return DateTime.tryParse(raw);
}

String prettyDate(String? raw) {
  final d = parseDate(raw);
  return d == null ? '—' : _prettyDate.format(d.toLocal());
}

String prettyDateTime(String? raw) {
  final d = parseDate(raw);
  return d == null ? '—' : _prettyDateTime.format(d.toLocal());
}

String clock(DateTime time) => _clock.format(time);

/// `2026-08-21T04:56:20Z` -> `2m ago` / `3h ago` / `5d ago`, falling back to
/// [prettyDate] once it's further back than that reads usefully.
String timeAgo(String? raw) {
  final d = parseDate(raw);
  if (d == null) return '—';
  final diff = DateTime.now().difference(d.toLocal());
  if (diff.inSeconds < 60) return 'now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  return prettyDate(raw);
}

/// `PARTIALLY_RECEIVED` -> `Partially received`
String humanizeCode(String? code) {
  if (code == null || code.isEmpty) return '—';
  final words = code.replaceAll('_', ' ').toLowerCase().trim();
  if (words.isEmpty) return '—';
  return words[0].toUpperCase() + words.substring(1);
}

/// Two-letter badge for a product tile that has no image.
String initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) {
    final p = parts.first;
    return (p.length == 1 ? p : p.substring(0, 2)).toUpperCase();
  }
  return (parts[0][0] + parts[1][0]).toUpperCase();
}

/// Money for the wire: fixed 2dp string, matching the `"499.00"` in the docs.
String moneyForApi(num value) => value.toStringAsFixed(2);

/// Quantity for the wire: a plain string, no trailing `.0`.
String qtyForApi(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();
