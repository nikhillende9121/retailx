import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart' show humanizeCode, money, qty, initials;
import '../../../core/json.dart' show asDouble, asDoubleOrNull;
import '../../../data/models/catalog.dart';
import '../../../data/models/credit.dart';
import '../../../data/models/pricing_quote.dart';
import '../../../data/models/receipt_format.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../printing/default_receipt_schema.dart';
import '../../../printing/receipt_pdf_service.dart';
import '../../../printing/receipt_token_resolver.dart';
import '../../../state/cart.dart';
import '../../../state/pricing_quote_state.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/cart_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import '../../widgets/printer_picker_sheet.dart';
import 'sale_detail_screen.dart';

/// The invoice and payment screen — reached from the till after products are
/// chosen.
///
/// This screen handles:
///   1. Invoice breakdown — every line, per-line discounts, coupon, tax
///      estimate and the payable total.
///   2. Customer — search an existing one or create a new one inline.
///   3. Charge — submits the sale and shows the receipt.
class SaleInvoiceScreen extends ConsumerStatefulWidget {
  const SaleInvoiceScreen({super.key});

  @override
  ConsumerState<SaleInvoiceScreen> createState() => _SaleInvoiceScreenState();
}

class _SaleInvoiceScreenState extends ConsumerState<SaleInvoiceScreen> {
  Customer? _customer;
  bool _busy = false;

  // Coupon UI state — the actual discount comes from the quote provider,
  // these just drive the text field and error message.
  String? _couponCode;
  String? _couponError;

  final TextEditingController _couponController = TextEditingController();

  // Payment method — CASH by default, CREDIT only ever chosen explicitly
  // (see `kSalePaymentMethods`: CREDIT is appended only when eligible).
  String _paymentMethod = kPaymentMethods.first;

  // The picked customer's credit position — fetched the moment a customer
  // is chosen (if credit is enabled), so the due/limit shows under CREDIT
  // *before* it's tapped, not only after (credit_androidChanges.md §2).
  CreditSummary? _creditSummary;
  bool _creditSummaryLoading = false;
  int _creditSummaryRequest = 0;

  @override
  void initState() {
    super.initState();
    // The cart is already populated by the time this screen opens (built on
    // the till before navigating here), so the `ref.listen` cart-change
    // hook below never fires on its own — without this, the quote stays
    // null forever and the summary is stuck on "Add items to see the
    // invoice." even with a full cart.
    Future.microtask(_refreshQuote);
  }

  @override
  void dispose() {
    _couponController.dispose();
    super.dispose();
  }

  CartController get _cart => ref.read(cartProvider(kCheckoutCart).notifier);
  QuoteController get _quote => ref.read(quoteProvider(kCheckoutCart).notifier);

  /// Builds a [QuoteInput] from the current screen state and fires a debounced
  /// quote refresh.
  void _refreshQuote() {
    final warehouseId = ref.read(warehouseIdProvider);
    if (warehouseId == null) return;
    final lines = ref.read(cartProvider(kCheckoutCart));
    _quote.request(QuoteInput(
      warehouseId: warehouseId,
      lines: lines,
      customerId: _customer?.id,
      couponCode: _couponCode,
    ));
  }

  // ─── credit ─────────────────────────────────────────────────────────────────

  /// Fetches the picked customer's due/limit so it can show under `CREDIT`
  /// before the cashier ever taps it. Best-effort: a 403 (missing
  /// `CREDIT.VIEW` on an otherwise credit-enabled tenant) or any other
  /// failure just means the figure doesn't show — the server still enforces
  /// the real limit on submit either way, so this is a display nicety, not
  /// something worth blocking checkout over.
  Future<void> _loadCreditSummary() async {
    final customer = _customer;
    final me = ref.read(meProvider);
    if (customer == null || !(me?.hasFeature(Feature.creditPayment) ?? false)) {
      setState(() => _creditSummary = null);
      return;
    }
    final request = ++_creditSummaryRequest;
    setState(() {
      _creditSummary = null;
      _creditSummaryLoading = true;
    });
    try {
      final summary =
          await ref.read(creditRepositoryProvider).summary(customer.id);
      if (!mounted || request != _creditSummaryRequest) return; // stale
      setState(() {
        _creditSummary = summary;
        _creditSummaryLoading = false;
      });
    } catch (_) {
      if (!mounted || request != _creditSummaryRequest) return;
      setState(() => _creditSummaryLoading = false);
    }
  }

  // ─── charge ───────────────────────────────────────────────────────────────

  Future<void> _charge(List<CartLine> lines) async {
    final me = ref.read(meProvider);
    final warehouseId = me?.warehouseId;
    if (warehouseId == null) {
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'No store is assigned to this account.',
        ),
      );
      return;
    }

    final customer = _customer;
    if ((me?.hasFeature(Feature.customer) ?? true) && customer == null) {
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.validation,
          message: 'Choose or create a customer first.',
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final sales = ref.read(salesRepositoryProvider);
    final cart = _cart;

    try {
      final sale = await sales.create(
        warehouseId: warehouseId,
        customerId: customer?.id,
        couponCode: _couponCode,
        items: lines.map((line) => line.toInput()).toList(),
        paymentMethod: _paymentMethod,
      );

      Sale current = sale;
      String? confirmProblem;
      if (me!.can(Perm.saleConfirm)) {
        try {
          current = await sales.confirm(sale.id);
        } on AppError catch (error) {
          confirmProblem = error.uiMessage;
        }
      } else {
        confirmProblem = 'Saved as a draft — your role cannot confirm sales.';
      }

      final selectedCustomer = customer;
      if (selectedCustomer != null &&
          (current.customerName == null || current.customerName!.isEmpty)) {
        current = current.withCustomer(selectedCustomer);
      }

      cart.clear();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _customer = null;
        _couponCode = null;
        _paymentMethod = kPaymentMethods.first;
        _creditSummary = null;
      });

      if (confirmProblem == null) {
        _autoPrintReceiptOnce(current);
      }

      await _showReceiptSheet(current, confirmProblem);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      // A blocking, actionable state — never a generic failure toast — since
      // this can happen even after the app's own summary looked fine (another
      // till may have used up the limit in between). error.details is fresher
      // than whatever the summary call returned earlier, so it drives the
      // dialog, not the stale _creditSummary. See credit_androidChanges.md §3.
      if (error.isCreditLimitExceeded) {
        await _showCreditLimitExceededDialog(error);
      } else {
        showErrorSnack(context, error);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(
        context,
        const AppError(
            code: ErrorCodes.unknown, message: 'Could not record the sale.'),
      );
    }
  }

  /// `CREDIT_LIMIT_EXCEEDED` — the cashier must reduce the credit portion
  /// (i.e. pick a different payment method entirely; this app has no
  /// split-payment concept) or cancel. Never silently retried.
  Future<void> _showCreditLimitExceededDialog(AppError error) async {
    final due = asDouble(error.details['currentBalance']);
    final limit = asDoubleOrNull(error.details['creditLimit']);
    final attempted = asDouble(error.details['attemptedChargeAmount']);
    final switchMethod = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.block_rounded),
        title: const Text('Credit limit exceeded'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(error.uiMessage),
            const SizedBox(height: 12),
            DetailRow(label: 'Current due', value: money(due)),
            if (limit != null) DetailRow(label: 'Credit limit', value: money(limit)),
            DetailRow(label: 'This sale', value: money(attempted)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Choose another method'),
          ),
        ],
      ),
    );
    if (switchMethod == true && mounted) {
      setState(() => _paymentMethod = kPaymentMethods.first);
    }
  }

  /// What to do with the invoice screen once the receipt sheet closes — the
  /// sheet itself only decides which of these was picked; the navigation
  /// happens after it's gone, never while it's still on top of the stack.
  Future<void> _showReceiptSheet(Sale sale, String? problem) async {
    final me = ref.read(meProvider);
    final scheme = Theme.of(context).colorScheme;
    final tokenStore = ref.read(tokenStoreProvider);
    final printerService = ref.read(printerServiceProvider);

    final isPrinterConfigured = tokenStore.printerAddress != null;
    bool isPrinterConnected = false;
    if (isPrinterConfigured) {
      try {
        isPrinterConnected = await printerService.isConnected;
      } catch (_) {}
    }
    final printerAvailable = isPrinterConfigured || isPrinterConnected;

    String customerText = sale.customerName ?? sale.customerLabel;
    if (sale.customerPhone != null && sale.customerPhone!.trim().isNotEmpty) {
      customerText += ' (${sale.customerPhone!.trim()})';
    }

    final viewSale = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      isDismissible: true,
      builder: (sheetContext) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  problem == null
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  size: 44,
                  // A confirmed sale is the literal "positive confirmation" the
                  // palette reserves success green for — not the brand blue.
                  color: problem == null
                      ? successColor(scheme.brightness)
                      : scheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  problem == null ? 'Sale confirmed' : 'Sale saved',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  sale.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                DetailRow(label: 'Customer', value: customerText),
                DetailRow(label: 'Subtotal', value: money(sale.itemsSubtotal)),
                if (sale.discountTotal > 0)
                  DetailRow(
                    label: 'Discount',
                    value: '− ${money(sale.discountTotal)}',
                    valueColor: successColor(scheme.brightness),
                  ),
                if (sale.chargesTotal > 0)
                  DetailRow(label: 'Charges', value: money(sale.chargesTotal)),
                if (sale.itemsTaxTotal + sale.chargesTaxTotal > 0)
                  DetailRow(
                    label: 'Tax',
                    value: money(sale.itemsTaxTotal + sale.chargesTaxTotal),
                  ),
                DetailRow(
                  label: 'Total',
                  value: money(sale.computedTotal),
                  emphasize: true,
                ),
                if (problem != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    problem,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error),
                  ),
                ],
                const SizedBox(height: 22),
                if (!printerAvailable) ...[
                  FilledButton.tonalIcon(
                    // Doesn't pop the sheet — printing happens in place so the
                    // cashier can still mark completed / view / move on after.
                    onPressed: () => _printReceipt(sale),
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print receipt'),
                  ),
                  const SizedBox(height: 8),
                ],
                if (sale.status.toUpperCase() == SaleStatus.confirmed &&
                    (me?.can(Perm.saleUpdate) ?? false))
                  FilledButton.icon(
                    onPressed: () async {
                      Navigator.of(sheetContext).pop(false);
                      await _completeSale(sale.id);
                    },
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('Mark completed'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View sale'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Next customer'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (viewSale ?? false) {
      // The sale is done and the cart's already cleared — there's nothing on
      // the invoice screen to come back to, so replace it outright rather
      // than stacking the detail screen on top of it.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: sale.id)),
      );
    } else {
      // "Next customer", "Mark completed", or dismissed by tapping outside —
      // all three mean the same thing: back to the till for the next sale.
      Navigator.of(context).pop();
    }
  }

  Future<void> _completeSale(String saleId) async {
    if (!mounted) return;
    try {
      await ref.read(salesRepositoryProvider).complete(saleId);
      if (!mounted) return;
      showInfoSnack(context, 'Sale completed.');
    } on AppError catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    }
  }

  // ─── receipt printing ──────────────────────────────────────────────────────

  final Set<String> _autoPrintedSaleIds = {};

  /// Automatically prints the receipt for [sale] once upon successful sale.
  ///
  /// Silent: a till that has never been paired with a printer charges dozens
  /// of sales a day, and popping the printer picker (or an error toast) after
  /// every single one — on top of the sale-success sheet already opening at
  /// the same moment — would make an unconfigured till nearly unusable. The
  /// explicit "Print receipt" button on that sheet (shown only when no
  /// printer is available, see `_showReceiptSheet`) is how that till prints.
  Future<void> _autoPrintReceiptOnce(Sale sale) async {
    if (_autoPrintedSaleIds.contains(sale.id)) return;
    _autoPrintedSaleIds.add(sale.id);
    await _printReceipt(sale, silent: true);
  }

  /// Prints [sale] to whichever Bluetooth thermal printer is paired.
  ///
  /// [silent] is set only by [_autoPrintReceiptOnce]: it skips the printer
  /// picker and any error toast when nothing's paired/reachable, instead of
  /// prompting — see that method for why. A manual tap on "Print receipt"
  /// always runs with [silent] false, since asking there is the whole point.
  Future<void> _printReceipt(Sale sale, {bool silent = false}) async {
    final me = ref.read(meProvider);
    final warehouseId = me?.warehouseId;
    if (me == null || warehouseId == null) return;

    try {
      final catalog = ref.read(catalogRepositoryProvider);

      // `/sales` doesn't expand the product relation — same gap and same
      // fix as `sale_detail_screen.dart`'s `load()`.
      var resolvedSale = sale;
      if (resolvedSale.needsItemProductLookup) {
        final names = await resolveProductNames(
          catalog,
          resolvedSale.items
              .where((item) => item.needsProductLookup)
              .map((item) => item.productId),
        );
        if (names.isNotEmpty) {
          resolvedSale = resolvedSale.withItems([
            for (final item in resolvedSale.items)
              if (names[item.productId] case final name?)
                item.withProductName(name)
              else
                item,
          ]);
        }
      }

      if (resolvedSale.needsCustomerLookup ||
          (resolvedSale.customerId != null && resolvedSale.customerPhone == null)) {
        try {
          final cust = await catalog.customer(resolvedSale.customerId!);
          if (cust != null) {
            resolvedSale = resolvedSale.withCustomer(cust);
          }
        } catch (_) {}
      }
      if (_customer != null &&
          (resolvedSale.customerName == null || resolvedSale.customerPhone == null)) {
        resolvedSale = resolvedSale.withCustomer(_customer!);
      }

      Warehouse shop;
      try {
        shop = await catalog.warehouse(warehouseId) ??
            Warehouse(
              id: warehouseId,
              name: me.warehouseName ?? me.storeLabel,
              address: me.warehouseAddress,
            );
      } on AppError {
        shop = Warehouse(
          id: warehouseId,
          name: me.warehouseName ?? me.storeLabel,
          address: me.warehouseAddress,
        );
      }

      if (shop.address == null || shop.address!.trim().isEmpty) {
        if (me.warehouseAddress != null && me.warehouseAddress!.trim().isNotEmpty) {
          shop = Warehouse(
            id: shop.id,
            name: shop.name,
            code: shop.code,
            address: me.warehouseAddress,
          );
        } else {
          try {
            final warehouses = await catalog.warehouses();
            for (final w in warehouses) {
              if (w.id == warehouseId && w.address != null && w.address!.trim().isNotEmpty) {
                shop = w;
                break;
              }
            }
          } catch (_) {}
        }
      }

      final tenant = await catalog.tenantProfile();

      // Fetch the server's receipt format, falling back to the bundled default.
      ReceiptFormat? format;
      try {
        final formatRepo = ref.read(receiptFormatRepositoryProvider);
        final posId = ref.read(tokenStoreProvider).deviceId ?? warehouseId;
        format = await formatRepo.fetchIfStale(posId);
      } catch (_) {
        // Network error — fall through to the bundled default.
      }
      format ??= kDefaultReceiptFormat;

      // Desktop/web: use PDF → native print dialog.
      if (ReceiptPdfService.shouldUsePdfPrinting) {
        final tokens = ReceiptTokenResolver.buildTokens(
          sale: resolvedSale,
          shop: shop,
          tenant: tenant,
          cashierName: me.name,
        );
        await ReceiptPdfService.printReceipt(
          format: format,
          tokens: tokens,
          items: resolvedSale.items,
          jobName: resolvedSale.label,
        );
        if (!mounted) return;
        showInfoSnack(context, 'Receipt sent to printer.');
        return;
      }

      // Android: Bluetooth ESC/POS thermal printer.
      final tokenStore = ref.read(tokenStoreProvider);
      final printerService = ref.read(printerServiceProvider);
      if (tokenStore.printerAddress == null) {
        final internal = await printerService.autoDetectInternalPrinter();
        if (internal != null) {
          try {
            await printerService.connect(internal.macAdress);
            await tokenStore.setPrinter(internal.macAdress, internal.name);
          } catch (_) {}
        }
        if (tokenStore.printerAddress == null) {
          if (silent) return;
          final picked = await showPrinterPicker(context);
          if (picked != true || !mounted) return;
        }
      }

      final printer = ref.read(printerServiceProvider);
      if (!await printer.isConnected) {
        final address = tokenStore.printerAddress;
        if (address == null) return;
        await printer.connect(address);
      }

      await printer.printWithFormat(
        sale: resolvedSale,
        shop: shop,
        tenant: tenant,
        format: format,
        cashierName: me.name,
      );
      if (!mounted) return;
      showInfoSnack(context, 'Receipt printed.');
    } on AppError catch (error) {
      if (!mounted || silent) return;
      showErrorSnack(context, error);
    } catch (_) {
      if (!mounted || silent) return;
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not print the receipt.',
        ),
      );
    }
  }

  // ─── coupon ─────────────────────────────────────────────────────────────────

  /// Sets (or clears) the coupon code and triggers a quote refresh so the
  /// server computes the actual discount.
  void _applyCoupon() {
    final code = _couponController.text.trim();
    final lines = ref.read(cartProvider(kCheckoutCart));
    if (code.isNotEmpty && lines.isEmpty) {
      setState(() => _couponError = 'Add items to the cart first.');
      return;
    }
    setState(() {
      _couponCode = code.isEmpty ? null : code;
      _couponError = null;
    });
    _refreshQuote();
  }

  void _clearCoupon() {
    _couponController.clear();
    setState(() {
      _couponCode = null;
      _couponError = null;
    });
    _refreshQuote();
  }

  // ─── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider(kCheckoutCart));
    final quoteAsync = ref.watch(quoteProvider(kCheckoutCart));
    final scheme = Theme.of(context).colorScheme;
    final me = ref.watch(meProvider);
    // A customer is only mandatory when the tenant's plan actually has the
    // CUSTOMER feature — hasFeature() itself already treats an unknown/empty
    // feature list as "allow", so this defaults to the old always-required
    // behavior when the server sends no feature info at all.
    final requiresCustomer = me?.hasFeature(Feature.customer) ?? true;
    final showCustomerGroup = me?.hasFeature(Feature.customerGroup) ?? false;
    final showCoupon = me?.hasFeature(Feature.coupon) ?? true;

    // Whenever the cart changes, refresh the quote so the server re-computes
    // totals, tax, discounts and coupon applicability.
    ref.listen<List<CartLine>>(cartProvider(kCheckoutCart), (previous, next) {
      _refreshQuote();
    });

    // Read server-computed figures from the quote. While loading or on error,
    // quote is null and the summary shows a loading/error state instead of
    // hardcoded estimates.
    final PricingQuote? quote = quoteAsync.valueOrNull;
    final bool quoteLoading = quoteAsync.isLoading;
    final couponDiscount = quote?.coupon?.amount ?? 0.0;

    // Only trust this quote's `coupon` field as an answer about the coupon
    // currently in the text field if it was actually computed for that same
    // code — a slower quote fired before the coupon was applied can still
    // land after `_couponCode` is set (see `lastCouponCode` in
    // pricing_quote_state.dart), and it legitimately carries `coupon: null`
    // without that meaning the coupon was rejected.
    final quoteMatchesCoupon = _quote.lastCouponCode == _couponCode;
    if (quote != null && _couponCode != null && quoteMatchesCoupon) {
      if (quote.coupon == null && _couponError == null) {
        // The server really did come back without the coupon for this exact
        // request — that means it was rejected.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _couponError = 'Coupon could not be applied.');
          }
        });
      } else if (quote.coupon != null && _couponError != null) {
        // A later quote for the same code confirms it *did* apply — clear a
        // stale error left over from an earlier, now-outdated response so
        // the message can't keep disagreeing with the totals below it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _couponError = null);
          }
        });
      }
    }

    final canCharge = (!requiresCustomer || _customer != null) &&
        lines.isNotEmpty &&
        lines.every((l) => l.isPriced) &&
        !_busy;

    // Keyed by product so each Items row can show what the server actually
    // computed for it (unit price, discount, total) instead of only the
    // locally-entered figures — null while the quote is loading/erroring or
    // for a line not yet reflected in it, in which case the row falls back
    // to the local cart figures exactly as before.
    final quoteLinesByProduct = {
      for (final quoteLine in quote?.lines ?? const <QuoteLine>[])
        quoteLine.productId: quoteLine,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Checkout'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: ListView(
        padding:
            const EdgeInsets.fromLTRB(kScreenMargin, 12, kScreenMargin, 24),
        children: [
          // ── Items ─────────────────────────────────────────────────────────
          _SectionHeader(
            title: 'Items  (${lines.length})',
            icon: Icons.shopping_cart_outlined,
            trailing: TextButton.icon(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.edit_rounded, size: 15),
              label: const Text('Edit cart'),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: scheme.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < lines.length; i++) ...[
                  if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
                  _LineRow(
                    line: lines[i],
                    quoteLine: quoteLinesByProduct[lines[i].product.id],
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Coupon ────────────────────────────────────────────────────────
          if (showCoupon) ...[
          _SectionHeader(
              title: 'Coupon', icon: Icons.confirmation_number_outlined),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _couponController,
                  enabled: !quoteLoading,
                  textCapitalization: TextCapitalization.characters,
                  onSubmitted: (_) => _applyCoupon(),
                  decoration: InputDecoration(
                    hintText: 'Enter coupon code',
                    isDense: true,
                    filled: true,
                    fillColor: scheme.surfaceContainerLowest,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    suffixIcon: _couponCode == null
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _clearCoupon,
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kRadiusCard),
                      borderSide: BorderSide(
                        color: _couponError != null
                            ? scheme.error
                            : scheme.outlineVariant,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: quoteLoading ? null : _applyCoupon,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                child: quoteLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Apply'),
              ),
            ],
          ),
          if (_couponError != null) ...[
            const SizedBox(height: 6),
            Text(
              _couponError!,
              style: TextStyle(
                fontSize: 12,
                color: scheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
          ] else if (_couponCode != null && quote?.coupon != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.check_circle_rounded,
                    size: 14, color: successColor(scheme.brightness)),
                const SizedBox(width: 4),
                Text(
                  'Coupon $_couponCode applied — ${money(couponDiscount)} off',
                  style: TextStyle(
                    fontSize: 12,
                    color: successColor(scheme.brightness),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
          ], // showCoupon

          const SizedBox(height: 20),

          // ── Invoice Summary ───────────────────────────────────────────────
          _SectionHeader(
              title: 'Invoice Summary', icon: Icons.receipt_long_outlined),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(kRadiusCard),
              border: Border.all(color: scheme.outlineVariant),
            ),
            padding: const EdgeInsets.symmetric(
                horizontal: kScreenMargin, vertical: 12),
            child: quoteAsync.when(
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (error, _) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  children: [
                    Icon(Icons.cloud_off_rounded,
                        size: 32, color: scheme.error),
                    const SizedBox(height: 8),
                    Text(
                      error is AppError
                          ? (error as AppError).uiMessage
                          : 'Could not compute totals. Check your connection.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.error, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _refreshQuote,
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (q) {
                if (q == null) {
                  // No quote yet (empty cart or first load)
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Add items to see the invoice.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  );
                }
                // Discount/coupon savings only — never derived from
                // grandTotal minus charges/tax, because how much of
                // grandTotal is tax depends on q.taxInclusive (see below),
                // which would otherwise make this drift depending on tax
                // mode. An ORDER-scope coupon adds on top of
                // lineDiscountTotal; a PRODUCT/CATEGORY-scope one is already
                // folded into it (lineCouponTotal > 0 tells the two apart —
                // see PricingQuote.autoDiscountTotal).
                final orderCouponAmount =
                    (q.coupon != null && q.lineCouponTotal == 0)
                        ? q.coupon!.amount
                        : 0.0;
                final totalSavings = q.lineDiscountTotal + orderCouponAmount;
                final discountBreakdown = q.discountBreakdown;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Every automatic Discount that actually matched a line,
                    // named individually — falls back to the aggregate only
                    // if the server sends a total without the per-line detail
                    // behind it.
                    if (discountBreakdown.isNotEmpty) ...[
                      for (final entry in discountBreakdown.entries)
                        DetailRow(
                          label: entry.key,
                          value: '− ${money(entry.value)}',
                          valueColor: successColor(scheme.brightness),
                        ),
                    ] else if (q.autoDiscountTotal > 0)
                      DetailRow(
                        label: 'Line discounts',
                        value: '− ${money(q.autoDiscountTotal)}',
                        valueColor: successColor(scheme.brightness),
                      ),
                    DetailRow(
                      label: 'Subtotal',
                      value: money(q.subtotal),
                    ),
                    if (q.coupon != null)
                      DetailRow(
                        label: 'Coupon (${q.coupon!.code})',
                        value: '− ${money(q.coupon!.amount)}',
                        valueColor: successColor(scheme.brightness),
                      ),
                    // Every extra charge by name — its own tax isn't shown
                    // per-charge; it's folded into the single Tax row below
                    // instead, so the same rupee isn't listed twice in the
                    // breakdown. Falls back to the aggregate if the server
                    // sends a total without the itemized list behind it.
                    if (q.charges.isNotEmpty) ...[
                      for (final charge in q.charges)
                        DetailRow(
                          label: charge.name,
                          value: money(charge.amount),
                        ),
                    ] else if ((q.chargesTotal ?? 0) > 0)
                      DetailRow(
                        label: 'Extra charges',
                        value: money(q.chargesTotal!),
                      ),
                    // Tax on the items/charges above. Exclusive: the server
                    // already summed this into grandTotal on top of the
                    // pre-tax figures, so it reads as a normal add-on line.
                    // Inclusive: it's already folded into every line's total
                    // and into grandTotal — showing it as another add-on
                    // would wrongly suggest it's charged twice, so it's
                    // parenthesized and muted instead, purely informational.
                    if ((q.taxTotal ?? 0) > 0)
                      DetailRow(
                        label: q.taxInclusive ? 'Tax (included)' : 'Tax',
                        value: q.taxInclusive
                            ? '(${money(q.taxTotal!)})'
                            : money(q.taxTotal!),
                        valueColor:
                            q.taxInclusive ? scheme.onSurfaceVariant : null,
                      ),
                    Divider(height: 16, color: scheme.outlineVariant),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            'Total payable',
                            style:
                                Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Text(
                          money(q.grandTotal),
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: scheme.onSurface,
                              ),
                        ),
                      ],
                    ),
                    if (totalSavings > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(Icons.savings_outlined,
                              size: 14,
                              color: successColor(scheme.brightness)),
                          const SizedBox(width: 6),
                          Text(
                            'You save ${money(totalSavings)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: successColor(scheme.brightness),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // ── Customer ──────────────────────────────────────────────────────
          // The whole card disappears, not just its requirement, when the
          // tenant's plan doesn't have CUSTOMER — there's nothing for a
          // cashier to do with a picker for a resource the plan doesn't grant.
          if (requiresCustomer) ...[
            _CustomerCard(
              customer: _customer,
              showGroup: showCustomerGroup,
              onChoose: (mode) async {
                final chosen = await pickCustomer(context, ref, initialMode: mode);
                if (chosen == null || !mounted) return;
                setState(() => _customer = chosen);
                // A coupon can be scoped to a customer/customer group, so a
                // change of customer can change what it's worth.
                _refreshQuote();
                _loadCreditSummary();
              },
              onClear: () {
                setState(() {
                  _customer = null;
                  // CREDIT requires a customer — a walk-in can't be on
                  // credit, so switching back to it isn't optional here.
                  if (_paymentMethod == 'CREDIT') {
                    _paymentMethod = kPaymentMethods.first;
                  }
                  _creditSummary = null;
                });
                _refreshQuote();
              },
            ),
            const SizedBox(height: 14),
          ],

          // ── Payment method ───────────────────────────────────────────────
          _PaymentMethodCard(
            selected: _paymentMethod,
            creditEnabled:
                (me?.hasFeature(Feature.creditPayment) ?? false) &&
                    _customer != null,
            creditSummary: _creditSummary,
            creditSummaryLoading: _creditSummaryLoading,
            onChanged: (method) => setState(() => _paymentMethod = method),
          ),
          const SizedBox(height: 14),

          // ── Charge button ─────────────────────────────────────────────────
          FilledButton(
            onPressed: canCharge ? () => _charge(lines) : null,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(kRadiusButton)),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Colors.white),
                  )
                : Text(
                    requiresCustomer && _customer == null
                        ? 'Choose a customer to charge'
                        : 'Charge  ${money(quote?.grandTotal ?? 0)}',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700),
                  ),
          ),

          if (requiresCustomer && _customer == null) ...[
            const SizedBox(height: 10),
            Center(
              child: Text(
                'A customer is required on every sale.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.error),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(
      {required this.title, required this.icon, this.trailing});

  final String title;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: scheme.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _CustomerCard extends StatelessWidget {
  const _CustomerCard(
      {required this.customer,
      required this.onChoose,
      required this.onClear,
      this.showGroup = false});

  final Customer? customer;

  /// Gated on the CUSTOMER_GROUP plan feature — the tier that governs which
  /// price list/discount applies is worth surfacing right at checkout, not
  /// just in a customer detail screen the cashier isn't looking at.
  final bool showGroup;

  /// Mode matches [pickCustomer]'s `initialMode`: 0 = existing, 1 = new — the
  /// two buttons below jump straight into the tab they name instead of
  /// landing on the picker sheet's default and making the cashier switch tabs.
  final void Function(int mode) onChoose;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCustomer = customer != null;

    return Container(
      decoration: BoxDecoration(
        color:
            hasCustomer ? scheme.surfaceContainerLowest : scheme.errorContainer,
        borderRadius: BorderRadius.circular(kRadiusCard),
        border: Border.all(
          color: hasCustomer ? scheme.outlineVariant : scheme.error.withAlpha(70),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: hasCustomer
                    ? scheme.primaryContainer
                    : scheme.error.withAlpha(30),
                child: hasCustomer
                    ? Text(
                        initials(customer!.name),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer,
                        ),
                      )
                    : Icon(Icons.person_search_rounded,
                        size: 16, color: scheme.onErrorContainer),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  hasCustomer ? customer!.name : 'No customer chosen',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: hasCustomer ? null : scheme.onErrorContainer,
                      ),
                ),
              ),
              if (showGroup &&
                  hasCustomer &&
                  (customer!.customerGroupName ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Chip(
                    label: Text(
                      customer!.customerGroupName!,
                      style: const TextStyle(fontSize: 11),
                    ),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    backgroundColor: scheme.secondaryContainer,
                  ),
                ),
              if (hasCustomer)
                IconButton(
                  tooltip: 'Clear customer',
                  visualDensity: VisualDensity.compact,
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => onChoose(0),
                  icon: const Icon(Icons.person_search_rounded, size: 18),
                  label: Text(hasCustomer ? 'Change Customer' : 'Select Existing'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => onChoose(1),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('New Customer'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Which method this sale is charged under. Chips rather than a dropdown,
/// same reasoning as the exchange settlement picker: a handful of options,
/// one tap each. CREDIT only ever appears when [creditEnabled] — the caller
/// already folds "is a customer picked" into that, since a walk-in can't go
/// on credit (credit_androidChanges.md §1).
class _PaymentMethodCard extends StatelessWidget {
  const _PaymentMethodCard({
    required this.selected,
    required this.creditEnabled,
    required this.creditSummary,
    required this.creditSummaryLoading,
    required this.onChanged,
  });

  final String selected;
  final bool creditEnabled;
  final CreditSummary? creditSummary;
  final bool creditSummaryLoading;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final methods = creditEnabled ? kSalePaymentMethods : kPaymentMethods;

    return SectionCard(
      title: 'Payment method',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final method in methods)
                ChoiceChip(
                  label: Text(humanizeCode(method)),
                  selected: selected == method,
                  onSelected: (_) => onChanged(method),
                ),
            ],
          ),
          // Shown the moment a customer is picked — before CREDIT is ever
          // tapped, not only after — so the cashier can see there's no room
          // on the account before reaching for it at all.
          if (creditEnabled) ...[
            const SizedBox(height: 10),
            if (creditSummaryLoading)
              Text(
                'Checking credit…',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              )
            else if (creditSummary != null)
              Row(
                children: [
                  Icon(Icons.account_balance_wallet_outlined,
                      size: 14, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      creditSummary!.hasLimit
                          ? 'Due ${money(creditSummary!.currentBalance)} · '
                              'Limit ${money(creditSummary!.creditLimit!)} · '
                              'Available ${money(creditSummary!.availableCredit!)}'
                          : 'Due ${money(creditSummary!.currentBalance)} · No limit set',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.line, this.quoteLine});

  final CartLine line;

  /// This same product exactly as the server priced it, when the current
  /// quote has settled and includes it — null while the quote is loading or
  /// erroring, or for a line not yet reflected in it. Whichever figures it
  /// supplies (price/discount/total) replace the locally-entered ones below,
  /// since those are only an unverified guess until this comes back.
  final QuoteLine? quoteLine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = quoteLine;

    final unitPrice = q?.unitPrice ?? line.price;
    final gross = q?.lineSubtotal ?? line.gross;
    final discountTotal = q?.discountTotal ?? line.discount;
    final total = q?.lineTotal ?? line.total;
    final isDiscounted = discountTotal > 0;

    // Which automatic Discount and/or coupon actually reduced this specific
    // line — only knowable once the server's quote answers, never guessed.
    final discountNames = q?.discounts.map((d) => d.name).toList() ?? const <String>[];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ProductThumb(
            name: line.product.name,
            imageUrl: line.product.imageUrl,
            size: 40,
            radius: 8,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${qty(line.quantity)} × ${money(unitPrice)}'
                  '${isDiscounted ? '  −${money(discountTotal)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (discountNames.isNotEmpty)
                  Text(
                    discountNames.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: successColor(scheme.brightness),
                        ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (isDiscounted)
                Text(
                  money(gross),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              Text(
                money(total),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: isDiscounted ? successColor(scheme.brightness) : null,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
