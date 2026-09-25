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
      'row' => RowSection.fromJson(json),
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
    this.bordered = true,
  });

  /// Which columns show and in what order — any subset of
  /// `name`, `qty`, `price`, `total`.
  final List<String> columns;

  /// Column key → custom label, e.g. `{ "name": "Product" }`.
  final Map<String, String> headers;

  /// Subtotal/Tax/Total rows merged into this table as a footer.
  /// Each entry: `{ label, value, bold? }`.
  final List<ItemTotalRow> totals;

  /// `true` (default): a real bordered grid, matching the Super Admin
  /// portal's own default. `false`: a plain list, no grid lines.
  final bool bordered;

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
      bordered: asBool(json['bordered'], true),
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

/// Small-print terms & conditions block — `\n` in [value] is a line break.
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

/// Lays its children out side by side instead of stacked.
class RowSection extends ReceiptSection {
  const RowSection({required this.children});

  final List<RowChild> children;

  factory RowSection.fromJson(Map<String, dynamic> json) {
    final raw = json['sections'];
    final list = raw is List ? raw : const [];
    return RowSection(
      children: list.whereType<Map<String, dynamic>>().map(RowChild.fromJson).toList(),
    );
  }
}

/// One child of a [RowSection]: the section itself (any type, parsed the
/// same as a top-level one — even another [RowSection]), plus its relative
/// share of the row's width. Two children with `width: 1` (the default)
/// split the row evenly; a `width: 2` child gets twice the share of a
/// `width: 1` sibling.
class RowChild {
  const RowChild({required this.section, this.width = 1});

  final ReceiptSection section;
  final double width;

  factory RowChild.fromJson(Map<String, dynamic> json) => RowChild(
        section: ReceiptSection.fromJson(json),
        width: asDouble(json['width'], 1),
      );
}

/// An unrecognized section type — silently skipped by renderers.
class UnknownSection extends ReceiptSection {
  const UnknownSection(this.type);

  final String type;
}
