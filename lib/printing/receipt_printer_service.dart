import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import '../core/errors.dart';
import '../core/formatters.dart';
import '../data/models/catalog.dart';
import '../data/models/receipt_format.dart';
import '../data/models/sale.dart';
import '../data/models/tenant.dart';
import 'receipt_image_loader.dart';
import 'receipt_token_resolver.dart';

/// Talks to a paired Bluetooth thermal receipt printer.
///
/// `print_bluetooth_thermal` is transport-only (classic-Bluetooth connect +
/// raw byte write against whatever the OS already has paired); the actual
/// ESC/POS command bytes come from `esc_pos_utils_plus`'s [Generator]. One
/// instance lives for the app's lifetime (see `printerServiceProvider`), so
/// the connection survives moving between the checkout screen and a past
/// sale's detail screen.
class ReceiptPrinterService {
  /// `print_bluetooth_thermal` checks `BLUETOOTH_CONNECT` on Android 12+
  /// before every call, but never requests it itself — its own
  /// `ActivityCompat.requestPermissions` call is dead, commented-out code.
  /// Without asking first, every call below silently no-ops (or, worse, the
  /// method channel never resolves at all — see the plugin's early `return`
  /// with no `result.success`/`result.error`), so this must run first.
  Future<void> _ensurePermission() async {
    if (await Permission.bluetoothConnect.isGranted) return;
    final status = await Permission.bluetoothConnect.request();
    if (!status.isGranted) {
      throw const AppError(
        code: ErrorCodes.unknown,
        message: 'Bluetooth permission is required to use a receipt printer.',
      );
    }
  }

  Future<List<BluetoothInfo>> pairedPrinters() async {
    await _ensurePermission();
    return PrintBluetoothThermal.pairedBluetooths;
  }

  /// Attempts to automatically discover a built-in internal thermal printer
  /// on Android POS handheld devices (e.g. Sunmi, iMin, Built-In Printer).
  Future<BluetoothInfo?> autoDetectInternalPrinter() async {
    try {
      final devices = await pairedPrinters();
      const internalKeywords = [
        'inner',
        'internal',
        'built-in',
        'builtin',
        'sunmi',
        'imin',
        'pos-printer',
        'pos_printer',
        'thermal',
        'printer',
      ];

      for (final device in devices) {
        final name = device.name.toLowerCase();
        for (final kw in internalKeywords) {
          if (name.contains(kw)) {
            return device;
          }
        }
      }
    } catch (_) {
      // Permission or bluetooth inactive
    }
    return null;
  }

  Future<bool> get isConnected => PrintBluetoothThermal.connectionStatus;

  Future<void> connect(String address) async {
    await _ensurePermission();
    final ok = await PrintBluetoothThermal.connect(macPrinterAddress: address);
    if (!ok) {
      throw const AppError(
        code: ErrorCodes.unknown,
        message: 'Could not connect to that printer.',
      );
    }
  }

  Future<void> disconnect() => PrintBluetoothThermal.disconnect;

  /// Reserved for the one grand-total line — every other figure on the
  /// receipt is plain, matching the agreed format. See [receiptAmount]'s
  /// doc comment for why this can't just be [money].
  String _amount(double value) => receiptAmount(value);

  /// Plain 2-decimal figure, no currency prefix.
  String _plain(double value) => receiptPlainAmount(value);

  /// Builds and sends the full receipt for [sale] to the connected printer
  /// — call [connect] first.
  ///
  /// [sale] should already have real product names resolved (see
  /// `Sale.needsItemProductLookup` / `resolveProductNames`) — this only
  /// prints what it's given.
  Future<void> printReceipt({
    required Sale sale,
    required Warehouse shop,
    TenantProfile? tenant,
  }) async {
    await _ensurePermission();
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    const center = PosStyles(align: PosAlign.center);
    const centerBold = PosStyles(align: PosAlign.center, bold: true);
    const centerBoldLarge = PosStyles(
      align: PosAlign.center,
      bold: true,
      height: PosTextSize.size2,
      width: PosTextSize.size2,
    );
    final rightStyle = const PosStyles(align: PosAlign.right);
    final boldRight = const PosStyles(align: PosAlign.right, bold: true);
    final bold = const PosStyles(bold: true);

    // ── 1. Shop Name at Top ──────────────────────────────────────────────
    final shopNameUpper = shop.name.trim().toUpperCase();
    bytes += generator.text(
      shopNameUpper,
      styles: shopNameUpper.length <= 16 ? centerBoldLarge : centerBold,
    );

    // ── 2. Shop Address ──────────────────────────────────────────────────
    if ((shop.address ?? '').trim().isNotEmpty) {
      bytes += generator.text(shop.address!.trim(), styles: center);
    }

    // ── 3. Company Name & GST Number (Tenant Details) ─────────────────
    if (tenant != null) {
      final compName = (tenant.companyName ?? tenant.displayName).trim();
      if (compName.isNotEmpty && compName.toLowerCase() != shop.name.trim().toLowerCase()) {
        bytes += generator.text(compName, styles: centerBold);
      }
      if ((tenant.gstNumber ?? '').trim().isNotEmpty) {
        bytes += generator.text('GSTIN: ${tenant.gstNumber!.trim()}', styles: centerBold);
      }
    }
    bytes += generator.hr();

    // ── 4. Invoice / Date / Customer / Phone / Email — label/value table ──
    void infoRow(String label, String value) => bytes.addAll(generator.row([
          PosColumn(text: label, width: 3, styles: bold),
          PosColumn(text: value, width: 9),
        ]));
    infoRow('Invoice', sale.number ?? '#${sale.id}');
    infoRow('Date', prettyDateTime(sale.saleDate ?? sale.createdAt));
    infoRow('Customer', sale.customerLabel);
    if ((sale.customerPhone ?? '').trim().isNotEmpty) {
      infoRow('Phone', sale.customerPhone!.trim());
    }
    if ((sale.customerEmail ?? '').trim().isNotEmpty) {
      infoRow('Email', sale.customerEmail!.trim());
    }
    bytes += generator.hr();

    // ── 5. Items ───────────────────────────────────────────────────────────
    bytes += generator.text('ITEMS', styles: bold);
    bytes += generator.row([
      PosColumn(text: 'Item', width: 5, styles: bold),
      PosColumn(text: 'Qty', width: 1, styles: boldRight),
      PosColumn(text: 'Rate', width: 3, styles: boldRight),
      PosColumn(text: 'Amount', width: 3, styles: boldRight),
    ]);
    for (final item in sale.items) {
      // The name gets its own full-width line rather than sharing the table
      // row below — cramming it into a 5-wide column wraps anything past
      // ~13 characters and misaligns the Qty/Rate/Amount columns next to it.
      bytes += generator.text(item.productName, styles: bold);
      bytes += generator.row([
        PosColumn(text: '', width: 5),
        PosColumn(text: qty(item.quantity), width: 1, styles: rightStyle),
        PosColumn(text: _plain(item.price), width: 3, styles: rightStyle),
        PosColumn(text: _plain(item.amount), width: 3, styles: rightStyle),
      ]);
    }
    bytes += generator.hr();

    // ── 6. Tax & charges ────────────────────────────────────────────────────
    // Every item's tax lines, aggregated by (component, rate) across the
    // whole sale — a per-item breakdown (the old layout) repeats the same
    // CGST/SGST pair once per line, which is correct but not what this
    // format asks for: one CGST row and one SGST row for the whole receipt.
    final taxTotals = <String, double>{};
    for (final item in sale.items) {
      for (final tax in item.taxes) {
        final key = '${tax.component} (${qty(tax.ratePercent)}%)';
        taxTotals[key] = (taxTotals[key] ?? 0) + tax.amount;
      }
    }

    final hasTaxOrCharges = taxTotals.isNotEmpty || sale.charges.isNotEmpty;
    if (hasTaxOrCharges) {
      bytes += generator.text('TAX & CHARGES', styles: bold);
    }
    for (final entry in taxTotals.entries) {
      bytes += generator.row([
        PosColumn(text: entry.key, width: 7),
        PosColumn(text: _plain(entry.value), width: 5, styles: rightStyle),
      ]);
    }
    for (final charge in sale.charges) {
      if (charge.taxAmount > 0) {
        bytes += generator.row([
          PosColumn(text: 'Tax on ${charge.name}', width: 7),
          PosColumn(text: _plain(charge.taxAmount), width: 5, styles: rightStyle),
        ]);
      }
    }
    for (final charge in sale.charges) {
      bytes += generator.row([
        PosColumn(text: charge.name, width: 7),
        PosColumn(text: _plain(charge.amount), width: 5, styles: rightStyle),
      ]);
    }
    if (hasTaxOrCharges) bytes += generator.hr();

    // ── 7. Totals ────────────────────────────────────────────────────────
    bytes += generator.row([
      PosColumn(text: 'Items Subtotal', width: 7),
      PosColumn(text: _plain(sale.itemsSubtotal), width: 5, styles: rightStyle),
    ]);

    for (final discount in sale.discounts) {
      final label = discount.isCoupon
          ? 'Coupon'
          : discount.isLineLevel
              ? 'Item Discount'
              : 'Order Discount';
      bytes += generator.row([
        PosColumn(text: label, width: 7),
        PosColumn(
          text: _plain(-discount.amount),
          width: 5,
          styles: rightStyle,
        ),
      ]);
    }

    final totalTax = sale.itemsTaxTotal + sale.chargesTaxTotal;
    if (totalTax > 0) {
      bytes += generator.row([
        PosColumn(text: 'Total Tax', width: 7),
        PosColumn(text: _plain(totalTax), width: 5, styles: rightStyle),
      ]);
    }

    bytes += generator.hr(ch: '=');
    bytes += generator.row([
      PosColumn(text: 'TOTAL AMOUNT', width: 7, styles: bold),
      PosColumn(text: _amount(sale.computedTotal), width: 5, styles: boldRight),
    ]);
    bytes += generator.hr(ch: '=');

    // ── 8. Footer: Powered by RetailX ────────────────────────────────────
    bytes += generator.feed(1);
    bytes += generator.text('Thank you for shopping with us!', styles: center);
    bytes += generator.feed(1);
    bytes += generator.text('Powered by RetailX', styles: centerBold);
    bytes += generator.feed(2);
    bytes += generator.cut();

    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      throw const AppError(
        code: ErrorCodes.unknown,
        message: 'The printer did not accept the receipt. Check it has '
            'paper and is switched on.',
      );
    }
  }

  // ─── schema-driven receipt ────────────────────────────────────────────────

  /// Top-level entry: prints using [format] when available, otherwise falls
  /// back to the hardcoded [printReceipt].
  Future<void> printWithFormat({
    required Sale sale,
    required Warehouse shop,
    TenantProfile? tenant,
    ReceiptFormat? format,
    String? cashierName,
  }) async {
    if (format != null) {
      final tokens = ReceiptTokenResolver.buildTokens(
        sale: sale,
        shop: shop,
        tenant: tenant,
        cashierName: cashierName,
      );
      await _printSchemaReceipt(
        format: format,
        tokens: tokens,
        items: sale.items,
      );
    } else {
      await printReceipt(sale: sale, shop: shop, tenant: tenant);
    }
  }

  /// Walks the schema's section list and emits ESC/POS bytes for each type.
  Future<void> _printSchemaReceipt({
    required ReceiptFormat format,
    required Map<String, String> tokens,
    required List<SaleItem> items,
  }) async {
    await _ensurePermission();
    final profile = await CapabilityProfile.load();
    final paper =
        format.paperWidth >= 72 ? PaperSize.mm80 : PaperSize.mm58;
    final generator = Generator(paper, profile);
    List<int> bytes = [];

    for (final section in format.sections) {
      bytes += await _renderSection(generator, section, tokens, items);
    }

    bytes += generator.feed(2);
    bytes += generator.cut();

    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      throw const AppError(
        code: ErrorCodes.unknown,
        message: 'The printer did not accept the receipt. Check it has '
            'paper and is switched on.',
      );
    }
  }

  Future<List<int>> _renderSection(
    Generator gen,
    ReceiptSection section,
    Map<String, String> tokens,
    List<SaleItem> items,
  ) async {
    return switch (section) {
      TextSection() => _renderText(gen, section, tokens),
      KeyValueSection() => _renderKeyValue(gen, section, tokens),
      DividerSection() => gen.hr(),
      ItemsSection() => _renderItems(gen, section, tokens, items),
      SpacerSection() => gen.feed(section.lines),
      BarcodeSection() => _renderBarcode(gen, section, tokens),
      QrSection() => _renderQr(gen, section, tokens),
      TermsSection() => _renderTerms(gen, section, tokens),
      ImageSection() => await _renderImage(gen, section, tokens),
      RowSection() => await _renderRow(gen, section, tokens, items),
      UnknownSection() => const <int>[], // Silently skipped.
    };
  }

  /// True side-by-side ESC/POS text columns (`Generator.row`) only work for
  /// simple, single-line content — the API needs column widths that sum to
  /// exactly 12 and one line of text per column — so this only lays
  /// `text`/`keyvalue` children out that way. A row holding anything more
  /// complex (a nested items table, image, qr/barcode graphic, or another
  /// row) has no sane column representation on a receipt-width printer, so
  /// those — and any row with more children than a 12-unit grid can give
  /// one column each — fall back to rendering every child stacked, in
  /// order, rather than dropping them or aborting the whole print job.
  Future<List<int>> _renderRow(
    Generator gen,
    RowSection section,
    Map<String, String> tokens,
    List<SaleItem> items,
  ) async {
    final children = section.children;
    if (children.isEmpty) return const [];

    final allSimple = children.every(
      (c) => c.section is TextSection || c.section is KeyValueSection,
    );

    if (allSimple) {
      final widths = _rowColumnWidths(children.map((c) => c.width).toList());
      if (widths != null) {
        try {
          final columns = [
            for (var i = 0; i < children.length; i++)
              _rowColumnFor(children[i].section, tokens, widths[i]),
          ];
          return gen.row(columns);
        } catch (_) {
          // Fall through to the stacked fallback below.
        }
      }
    }

    List<int> bytes = [];
    for (final child in children) {
      bytes += await _renderSection(gen, child.section, tokens, items);
    }
    return bytes;
  }

  PosColumn _rowColumnFor(
    ReceiptSection section,
    Map<String, String> tokens,
    int width,
  ) {
    return switch (section) {
      TextSection s => PosColumn(
          text: ReceiptTokenResolver.resolve(s.value, tokens).replaceAll('\n', ' '),
          width: width,
          styles: _posStyles(align: s.align, bold: s.bold, size: s.size),
        ),
      KeyValueSection s => PosColumn(
          text: '${s.key}: ${ReceiptTokenResolver.resolve(s.value, tokens)}',
          width: width,
          styles: s.bold ? const PosStyles(bold: true) : const PosStyles(),
        ),
      _ => PosColumn(text: '', width: width),
    };
  }

  /// Distributes 12 grid units across [weights] proportionally, guaranteed
  /// to sum to exactly 12 (`Generator.row` throws otherwise) with every
  /// column getting at least 1. Returns `null` when that's not possible
  /// (more columns than grid units to give each at least 1) — the caller
  /// falls back to stacking instead of forcing a degenerate layout.
  List<int>? _rowColumnWidths(List<double> weights) {
    final n = weights.length;
    if (n > 12) return null;
    final total = weights.fold<double>(0, (a, b) => a + b);
    final safeWeights = total > 0 ? weights : List.filled(n, 1.0);
    final safeTotal = total > 0 ? total : n.toDouble();

    final widths = [
      for (final w in safeWeights) ((w / safeTotal) * 12).floor(),
    ];
    for (var i = 0; i < widths.length; i++) {
      if (widths[i] < 1) widths[i] = 1;
    }
    final sum = widths.fold<int>(0, (a, b) => a + b);
    widths[widths.length - 1] += 12 - sum;
    if (widths[widths.length - 1] < 1) return null;
    return widths;
  }

  /// Fetches and decodes the logo, then hands it to
  /// [Generator.image] for ESC/POS raster printing. Never throws — a
  /// missing/unreachable/corrupt logo must not stop the rest of the receipt
  /// (every other section) from printing.
  Future<List<int>> _renderImage(
    Generator gen,
    ImageSection section,
    Map<String, String> tokens,
  ) async {
    final url = ReceiptTokenResolver.resolve(section.value, tokens);
    if (url.isEmpty) return const <int>[];

    final bytes = await ReceiptImageLoader.fetchBytes(url);
    if (bytes == null) return const <int>[];

    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return const <int>[];
      final align = switch (section.align) {
        'left' => PosAlign.left,
        'right' => PosAlign.right,
        _ => PosAlign.center,
      };
      return gen.image(decoded, align: align);
    } catch (_) {
      return const <int>[];
    }
  }

  PosStyles _posStyles({
    String align = 'left',
    bool bold = false,
    String size = 'normal',
  }) {
    return PosStyles(
      align: switch (align) {
        'center' => PosAlign.center,
        'right' => PosAlign.right,
        _ => PosAlign.left,
      },
      bold: bold,
      // `xs` maps to `small` on the printer — see guide §1 warning.
      height: size == 'large' ? PosTextSize.size2 : PosTextSize.size1,
      width: size == 'large' ? PosTextSize.size2 : PosTextSize.size1,
    );
  }

  List<int> _renderText(
    Generator gen,
    TextSection section,
    Map<String, String> tokens,
  ) {
    final resolved = ReceiptTokenResolver.resolve(section.value, tokens);
    if (resolved.isEmpty) return const [];
    // Multi-line values (e.g. terms with \n) print each line separately.
    final lines = resolved.split('\n');
    final style = _posStyles(
      align: section.align,
      bold: section.bold,
      size: section.size,
    );
    List<int> bytes = [];
    for (final line in lines) {
      bytes += gen.text(line, styles: style);
    }
    return bytes;
  }

  List<int> _renderKeyValue(
    Generator gen,
    KeyValueSection section,
    Map<String, String> tokens,
  ) {
    final resolvedValue = ReceiptTokenResolver.resolve(section.value, tokens);
    final style = section.bold
        ? const PosStyles(bold: true)
        : const PosStyles();
    final rightStyle = section.bold
        ? const PosStyles(align: PosAlign.right, bold: true)
        : const PosStyles(align: PosAlign.right);
    return gen.row([
      PosColumn(text: section.key, width: 5, styles: style),
      PosColumn(text: resolvedValue, width: 7, styles: rightStyle),
    ]);
  }

  List<int> _renderItems(
    Generator gen,
    ItemsSection section,
    Map<String, String> tokens,
    List<SaleItem> items,
  ) {
    final columns = section.columns.isNotEmpty
        ? section.columns
        : ['name', 'qty', 'price', 'total'];

    List<int> bytes = [];
    const headerStyle = PosStyles(bold: true);
    const rightBoldStyle = PosStyles(align: PosAlign.right, bold: true);
    const rightStyle = PosStyles(align: PosAlign.right);

    // Column widths — must sum to 12 (ESC/POS constraint).
    final widths = _columnWidths(columns);

    // Header row.
    bytes += gen.row([
      for (var i = 0; i < columns.length; i++)
        PosColumn(
          text: section.headers[columns[i]] ?? columns[i],
          width: widths[i],
          styles: columns[i] == 'name' ? headerStyle : rightBoldStyle,
        ),
    ]);

    // Item rows — name on its own line, then the numeric columns.
    for (final item in items) {
      // Print name on a full-width line (same as the hardcoded renderer)
      // to avoid truncation on narrow thermal paper.
      if (columns.contains('name')) {
        bytes += gen.text(item.productName, styles: headerStyle);
      }
      bytes += gen.row([
        for (var i = 0; i < columns.length; i++)
          PosColumn(
            text: columns[i] == 'name'
                ? ''
                : _itemCellValue(columns[i], item),
            width: widths[i],
            styles: columns[i] == 'name' ? const PosStyles() : rightStyle,
          ),
      ]);
    }

    // Totals footer rows.
    for (final total in section.totals) {
      final resolvedValue = ReceiptTokenResolver.resolve(total.value, tokens);
      bytes += gen.row([
        PosColumn(
          text: total.label,
          width: 7,
          styles: total.bold ? headerStyle : const PosStyles(),
        ),
        PosColumn(
          text: resolvedValue,
          width: 5,
          styles: total.bold ? rightBoldStyle : rightStyle,
        ),
      ]);
    }

    return bytes;
  }

  /// ESC/POS columns must sum to 12. Give name most of the space.
  List<int> _columnWidths(List<String> columns) {
    if (columns.length == 1) return [12];
    if (columns.length == 2) {
      if (columns.contains('name')) return columns[0] == 'name' ? [7, 5] : [5, 7];
      return [6, 6];
    }
    if (columns.length == 3) {
      final hasName = columns.contains('name');
      if (hasName) {
        // name: 5, others: 3 + 4 = 7, total: 12
        return columns.map((c) => c == 'name' ? 5 : columns.indexOf(c) == columns.length - 1 ? 4 : 3).toList();
      }
      return [4, 4, 4];
    }
    // 4 columns: name=5, others=2/2/3
    if (columns.length >= 4) {
      final widths = <int>[];
      int remaining = 12;
      for (var i = 0; i < columns.length; i++) {
        if (i == columns.length - 1) {
          widths.add(remaining);
        } else if (columns[i] == 'name') {
          widths.add(5);
          remaining -= 5;
        } else {
          final w = remaining ~/ (columns.length - i);
          widths.add(w);
          remaining -= w;
        }
      }
      return widths;
    }
    return List.filled(columns.length, 12 ~/ columns.length);
  }

  String _itemCellValue(String column, SaleItem item) => switch (column) {
        'name' => item.productName,
        'qty' => qty(item.quantity),
        'price' => _plain(item.price),
        'total' => _plain(item.amount),
        _ => '',
      };

  List<int> _renderBarcode(
    Generator gen,
    BarcodeSection section,
    Map<String, String> tokens,
  ) {
    final data = ReceiptTokenResolver.resolve(section.value, tokens);
    if (data.isEmpty) return const [];
    try {
      return gen.barcode(Barcode.code128(data.codeUnits));
    } catch (_) {
      // Barcode encoding can fail for special characters — skip silently.
      return const [];
    }
  }

  List<int> _renderQr(
    Generator gen,
    QrSection section,
    Map<String, String> tokens,
  ) {
    final data = ReceiptTokenResolver.resolve(section.value, tokens);
    if (data.isEmpty) return const [];
    return gen.qrcode(data);
  }

  List<int> _renderTerms(
    Generator gen,
    TermsSection section,
    Map<String, String> tokens,
  ) {
    // Rendered the same as a small text block.
    final resolved = ReceiptTokenResolver.resolve(section.value, tokens);
    if (resolved.isEmpty) return const [];
    final style = _posStyles(align: section.align, size: section.size);
    List<int> bytes = [];
    for (final line in resolved.split('\n')) {
      bytes += gen.text(line, styles: style);
    }
    return bytes;
  }
}
