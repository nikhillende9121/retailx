import '../../core/json.dart';

// ─── Receipt Format ─────────────────────────────────────────────────────────

/// The resolved receipt format returned by `GET /pos/{posId}/receipt-format`.
///
/// See `pos_receipt_format_guide.md` §2.1 for the full wire shape.
class ReceiptFormat {
  const ReceiptFormat({
    required this.formatId,
    required this.name,
    required this.version,
    required this.paperWidth,
    required this.sections,
  });

  final String formatId;
  final String name;
  final int version;

  /// Paper width in mm — 58 and 80 are common thermal roll sizes, but
  /// 210 (A4) is equally valid (see guide §1 on paper width).
  final int paperWidth;

  /// Ordered list of sections, rendered top to bottom.
  final List<ReceiptSection> sections;

  factory ReceiptFormat.fromJson(Map<String, dynamic> json) {
    final schema = asMap(json['schema']) ?? const {};
    final rawSections = schema['sections'];
    final sectionList = rawSections is List ? rawSections : const [];
    return ReceiptFormat(
      formatId: asString(json['formatId']) ?? '',
      name: asString(json['name']) ?? 'Receipt',
      version: asInt(json['version']),
      paperWidth: asInt(json['paperWidth'], 58),
      sections: sectionList
          .whereType<Map<String, dynamic>>()
          .map(ReceiptSection.fromJson)
          .toList(),
    );
  }
}

// ─── Section types ──────────────────────────────────────────────────────────

/// One section of a receipt schema — the `type` field dispatches to a concrete
/// subclass. Unknown types parse as [UnknownSection] and are silently skipped
/// by renderers, per the guide's forward-compatibility rule.
sealed class ReceiptSection {
  const ReceiptSection();

  factory ReceiptSection.fromJson(Map<String, dynamic> json) {
    final type = asString(json['type']) ?? '';
    return switch (type) {
      'text' => TextSection.fromJson(json),
      'keyvalue' => KeyValueSection.fromJson(json),
      'divider' => const DividerSection(),
      'items' => ItemsSection.fromJson(json),
      'image' => ImageSection.fromJson(json),
      'barcode' => BarcodeSection.fromJson(json),
      'qr' => QrSection.fromJson(json),
      'spacer' => SpacerSection.fromJson(json),
      'terms' => TermsSection.fromJson(json),
      _ => UnknownSection(type),
    };
  }
}

/// One line of text — the most common section type.
class TextSection extends ReceiptSection {
  const TextSection({
    required this.value,
    this.align = 'left',
    this.bold = false,
    this.size = 'normal',
  });

  final String value;
  final String align;
  final bool bold;

  /// `xs` | `small` | `normal` | `large`.
  final String size;

  factory TextSection.fromJson(Map<String, dynamic> json) => TextSection(
        value: asString(json['value']) ?? '',
        align: asString(json['align']) ?? 'left',
        bold: asBool(json['bold']),
        size: asString(json['size']) ?? 'normal',
      );
}

/// Label on the left, value on the right, same line.
class KeyValueSection extends ReceiptSection {
  const KeyValueSection({
    required this.key,
    required this.value,
    this.bold = false,
  });

  final String key;
  final String value;
  final bool bold;

  factory KeyValueSection.fromJson(Map<String, dynamic> json) =>
      KeyValueSection(
        key: asString(json['key']) ?? '',
        value: asString(json['value']) ?? '',
        bold: asBool(json['bold']),
      );
}

/// Full-width separator line.
class DividerSection extends ReceiptSection {
  const DividerSection();
}

/// Line items as a table with a header row.
class ItemsSection extends ReceiptSection {
  const ItemsSection({
    required this.columns,
    required this.headers,
    this.totals = const [],
  });

  /// Which columns show and in what order — any subset of
  /// `name`, `qty`, `price`, `total`.
  final List<String> columns;

  /// Column key → custom label, e.g. `{ "name": "Product" }`.
  final Map<String, String> headers;

  /// Subtotal/Tax/Total rows merged into this table as a footer.
  /// Each entry: `{ label, value, bold? }`.
  final List<ItemTotalRow> totals;

  factory ItemsSection.fromJson(Map<String, dynamic> json) {
    final rawColumns = json['columns'];
    final columnList = rawColumns is List ? rawColumns : const [];
    final rawHeaders = asMap(json['headers']) ?? const {};
    final rawTotals = json['totals'];
    final totalsList = rawTotals is List ? rawTotals : const [];
    return ItemsSection(
      columns: columnList.whereType<String>().toList(),
      headers: rawHeaders.map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? k.toString()),
      ),
      totals: totalsList
          .whereType<Map<String, dynamic>>()
          .map(ItemTotalRow.fromJson)
          .toList(),
    );
  }
}

/// One summary row in an `items` section's `totals` array.
class ItemTotalRow {
  const ItemTotalRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  factory ItemTotalRow.fromJson(Map<String, dynamic> json) => ItemTotalRow(
        label: asString(json['label']) ?? '',
        value: asString(json['value']) ?? '',
        bold: asBool(json['bold']),
      );
}

/// A logo image — URL is fetched and converted on-device.
class ImageSection extends ReceiptSection {
  const ImageSection({required this.value, this.align = 'center'});

  final String value;
  final String align;

  factory ImageSection.fromJson(Map<String, dynamic> json) => ImageSection(
        value: asString(json['value']) ?? '',
        align: asString(json['align']) ?? 'center',
      );
}

/// A barcode (defaults to code128).
class BarcodeSection extends ReceiptSection {
  const BarcodeSection({required this.value});

  final String value;

  factory BarcodeSection.fromJson(Map<String, dynamic> json) => BarcodeSection(
        value: asString(json['value']) ?? '',
      );
}

/// A QR code.
class QrSection extends ReceiptSection {
  const QrSection({required this.value});

  final String value;

  factory QrSection.fromJson(Map<String, dynamic> json) => QrSection(
        value: asString(json['value']) ?? '',
      );
}

/// Blank vertical space.
class SpacerSection extends ReceiptSection {
  const SpacerSection({this.lines = 1});

  final int lines;

  factory SpacerSection.fromJson(Map<String, dynamic> json) => SpacerSection(
        lines: asInt(json['lines'], 1),
      );
}

/// Small-print terms & conditions block.
///
/// Portal-only addition (guide §1 warning) — on a real device this is
/// an unrecognized type and prints nothing until the Android renderer
/// adds a matching case. This renderer *does* support it (it's just a
/// small multi-line text block), so it'll print from this app even
/// before the spec is updated.
class TermsSection extends ReceiptSection {
  const TermsSection({
    required this.value,
    this.align = 'left',
    this.size = 'xs',
  });

  final String value;
  final String align;
  final String size;

  factory TermsSection.fromJson(Map<String, dynamic> json) => TermsSection(
        value: asString(json['value']) ?? '',
        align: asString(json['align']) ?? 'left',
        size: asString(json['size']) ?? 'xs',
      );
}

/// An unrecognized section type — silently skipped by renderers.
class UnknownSection extends ReceiptSection {
  const UnknownSection(this.type);

  final String type;
}
