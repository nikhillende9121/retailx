import 'package:flutter/foundation.dart' show kIsWeb, TargetPlatform, defaultTargetPlatform;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/formatters.dart' show qty, receiptPlainAmount;
import '../data/models/receipt_format.dart';
import '../data/models/sale.dart';
import 'receipt_image_loader.dart';
import 'receipt_token_resolver.dart';

/// Renders a receipt schema into a PDF and sends it to the OS print dialog.
///
/// Used on desktop (Windows/macOS/Linux) and as a fallback on Android when no
/// Bluetooth thermal printer is available. On Android the primary path is
/// still the ESC/POS Bluetooth renderer in [ReceiptPrinterService].
class ReceiptPdfService {
  ReceiptPdfService._();

  /// True when this platform should use PDF printing instead of Bluetooth
  /// ESC/POS. Web and any non-Android platform.
  static bool get shouldUsePdfPrinting {
    if (kIsWeb) return true;
    return defaultTargetPlatform != TargetPlatform.android;
  }

  /// Builds a PDF document from the receipt [format], with tokens resolved.
  static Future<pw.Document> buildPdf({
    required ReceiptFormat format,
    required Map<String, String> tokens,
    required List<SaleItem> items,
  }) async {
    final pdf = pw.Document();
    final pageWidth = format.paperWidth.toDouble();

    // Thermal receipt: a single long page whose height grows with content.
    // We use a custom page format matching the paper width (in mm).
    final pageFormat = PdfPageFormat(
      pageWidth * PdfPageFormat.mm,
      double.infinity, // infinite height, will be cropped to content
      marginAll: 4 * PdfPageFormat.mm,
    );

    // Built once, up front — pw.Page's own `build` callback must stay
    // synchronous (the pdf package calls it directly), so anything async
    // (fetching a logo for an `image` section) has to resolve before we
    // ever call addPage.
    final sectionWidgets = await _buildSections(format.sections, tokens, items);

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: sectionWidgets,
          );
        },
      ),
    );

    return pdf;
  }

  /// Opens the native print dialog with the rendered receipt.
  static Future<void> printReceipt({
    required ReceiptFormat format,
    required Map<String, String> tokens,
    required List<SaleItem> items,
    String jobName = 'Receipt',
  }) async {
    final pdf = await buildPdf(format: format, tokens: tokens, items: items);
    await Printing.layoutPdf(
      onLayout: (_) => pdf.save(),
      name: jobName,
    );
  }

  // ─── section rendering ─────────────────────────────────────────────────────

  static Future<List<pw.Widget>> _buildSections(
    List<ReceiptSection> sections,
    Map<String, String> tokens,
    List<SaleItem> items,
  ) async {
    final widgets = <pw.Widget>[];
    for (final section in sections) {
      final widget = await _buildSection(section, tokens, items);
      if (widget != null) widgets.add(widget);
    }
    return widgets;
  }

  static Future<pw.Widget?> _buildSection(
    ReceiptSection section,
    Map<String, String> tokens,
    List<SaleItem> items,
  ) async {
    return switch (section) {
      TextSection() => _buildText(section, tokens),
      KeyValueSection() => _buildKeyValue(section, tokens),
      DividerSection() => _buildDivider(),
      ItemsSection() => _buildItems(section, tokens, items),
      SpacerSection() => _buildSpacer(section),
      BarcodeSection() => _buildBarcode(section, tokens),
      QrSection() => _buildQr(section, tokens),
      TermsSection() => _buildTerms(section, tokens),
      ImageSection() => await _buildImage(section, tokens),
      RowSection() => await _buildRow(section, tokens, items),
      UnknownSection() => null, // Silently skipped per the guide.
    };
  }

  /// Fetches the logo and hands its raw bytes to [pw.MemoryImage], which
  /// decodes the format itself. Returns `null` (section just doesn't
  /// appear) on any failure — never throws, same reasoning as the ESC/POS
  /// renderer's `_renderImage`.
  static Future<pw.Widget?> _buildImage(
    ImageSection section,
    Map<String, String> tokens,
  ) async {
    final url = ReceiptTokenResolver.resolve(section.value, tokens);
    if (url.isEmpty) return null;

    final bytes = await ReceiptImageLoader.fetchBytes(url);
    if (bytes == null) return null;

    try {
      final provider = pw.MemoryImage(bytes);
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2),
        child: pw.Align(
          alignment: switch (section.align) {
            'left' => pw.Alignment.centerLeft,
            'right' => pw.Alignment.centerRight,
            _ => pw.Alignment.center,
          },
          child: pw.Image(provider, height: 40, fit: pw.BoxFit.scaleDown),
        ),
      );
    } catch (_) {
      return null;
    }
  }

  /// Lays each child out in a [pw.Row] — the PDF/desktop path has no real
  /// technical limit on this the way ESC/POS text columns do, so it renders
  /// exactly like the Super Admin preview: each child gets a share of the
  /// width proportional to its own `width` (default `1`, i.e. even split).
  static Future<pw.Widget?> _buildRow(
    RowSection section,
    Map<String, String> tokens,
    List<SaleItem> items,
  ) async {
    if (section.children.isEmpty) return null;
    final columns = <pw.Widget>[];
    for (final child in section.children) {
      final widget = await _buildSection(child.section, tokens, items);
      columns.add(
        pw.Expanded(
          flex: child.width.round().clamp(1, 1000),
          child: widget ?? pw.SizedBox.shrink(),
        ),
      );
    }
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: columns,
      ),
    );
  }

  static pw.Widget _buildText(TextSection section, Map<String, String> tokens) {
    final resolved = ReceiptTokenResolver.resolve(section.value, tokens);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Text(
        resolved,
        textAlign: _pdfAlign(section.align),
        style: pw.TextStyle(
          fontSize: _pdfFontSize(section.size),
          fontWeight: section.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _buildKeyValue(
    KeyValueSection section,
    Map<String, String> tokens,
  ) {
    final resolvedValue = ReceiptTokenResolver.resolve(section.value, tokens);
    final style = pw.TextStyle(
      fontSize: _pdfFontSize('normal'),
      fontWeight: section.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    );
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(section.key, style: style),
          pw.Text(resolvedValue, style: style),
        ],
      ),
    );
  }

  static pw.Widget _buildDivider() {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Divider(thickness: 0.5),
    );
  }

  static pw.Widget _buildItems(
    ItemsSection section,
    Map<String, String> tokens,
    List<SaleItem> items,
  ) {
    final columns = section.columns.isNotEmpty
        ? section.columns
        : ['name', 'qty', 'price', 'total'];

    final headerStyle = pw.TextStyle(
      fontSize: _pdfFontSize('small'),
      fontWeight: pw.FontWeight.bold,
    );
    final cellStyle = pw.TextStyle(fontSize: _pdfFontSize('small'));

    // Column flex widths — name gets more space.
    int flexFor(String col) => col == 'name' ? 4 : 2;

    // Header row.
    final headerCells = columns.map((col) {
      final label = section.headers[col] ?? col;
      final isNumeric = col != 'name';
      return pw.Expanded(
        flex: flexFor(col),
        child: pw.Text(
          label,
          style: headerStyle,
          textAlign: isNumeric ? pw.TextAlign.right : pw.TextAlign.left,
        ),
      );
    }).toList();

    // Item rows.
    final itemRows = items.map((item) {
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          children: columns.map((col) {
            final isNumeric = col != 'name';
            final value = switch (col) {
              'name' => item.productName,
              'qty' => qty(item.quantity),
              'price' => receiptPlainAmount(item.price),
              'total' => receiptPlainAmount(item.amount),
              _ => '',
            };
            return pw.Expanded(
              flex: flexFor(col),
              child: pw.Text(
                value,
                style: cellStyle,
                textAlign: isNumeric ? pw.TextAlign.right : pw.TextAlign.left,
              ),
            );
          }).toList(),
        ),
      );
    }).toList();

    // Totals footer rows — Subtotal/Discount/Tax/Total merged into the same
    // table, matching the ESC/POS renderer.
    final totalRows = section.totals.map((total) {
      final resolvedValue = ReceiptTokenResolver.resolve(total.value, tokens);
      final style = pw.TextStyle(
        fontSize: _pdfFontSize('normal'),
        fontWeight: total.bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );
      return pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 1),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(total.label, style: style),
            pw.Text(resolvedValue, style: style),
          ],
        ),
      );
    }).toList();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Header
        pw.Row(children: headerCells),
        pw.Divider(thickness: 0.3),
        // Items
        ...itemRows,
        // Totals footer
        if (totalRows.isNotEmpty) ...[
          pw.Divider(thickness: 0.3),
          ...totalRows,
        ],
      ],
    );
  }

  static pw.Widget _buildSpacer(SpacerSection section) {
    return pw.SizedBox(height: section.lines * 8.0);
  }

  static pw.Widget _buildBarcode(
    BarcodeSection section,
    Map<String, String> tokens,
  ) {
    final data = ReceiptTokenResolver.resolve(section.value, tokens);
    if (data.isEmpty) return pw.SizedBox.shrink();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.code128(),
          data: data,
          width: 120,
          height: 40,
        ),
      ),
    );
  }

  static pw.Widget _buildQr(QrSection section, Map<String, String> tokens) {
    final data = ReceiptTokenResolver.resolve(section.value, tokens);
    if (data.isEmpty) return pw.SizedBox.shrink();
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4),
      child: pw.Center(
        child: pw.BarcodeWidget(
          barcode: pw.Barcode.qrCode(),
          data: data,
          width: 80,
          height: 80,
        ),
      ),
    );
  }

  static pw.Widget _buildTerms(
    TermsSection section,
    Map<String, String> tokens,
  ) {
    final resolved = ReceiptTokenResolver.resolve(section.value, tokens);
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Text(
        resolved,
        textAlign: _pdfAlign(section.align),
        style: pw.TextStyle(fontSize: _pdfFontSize(section.size)),
      ),
    );
  }

  // ─── helpers ───────────────────────────────────────────────────────────────

  static pw.TextAlign _pdfAlign(String align) => switch (align) {
        'center' => pw.TextAlign.center,
        'right' => pw.TextAlign.right,
        _ => pw.TextAlign.left,
      };

  /// Maps the schema's size buckets to PDF point sizes. Sized for a 58mm
  /// thermal receipt — wider formats (80mm, A4) still look fine, since the
  /// relative hierarchy is what matters.
  static double _pdfFontSize(String size) => switch (size) {
        'xs' => 6,
        'small' => 7,
        'large' => 12,
        _ => 8, // 'normal'
      };
}
