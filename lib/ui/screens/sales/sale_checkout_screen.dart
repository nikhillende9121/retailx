import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/receipt_format.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../printing/default_receipt_schema.dart';
import '../../../printing/receipt_pdf_service.dart';
import '../../../printing/receipt_token_resolver.dart';
import '../../../state/cart.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/cart_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import '../../widgets/printer_picker_sheet.dart';
import 'sale_detail_screen.dart';

/// Step two of a sale: who's buying, what it comes to, and take the money.
///
/// Split off the till on purpose. Picking products is a fast, repetitive,
/// eyes-on-the-shelf job; settling a bill is a slow, eyes-on-the-customer one
/// that needs a name, a discount decision and a total that can be read out loud.
/// Doing both on one screen meant the customer bar sat above the grid on every
/// single scan, and the invoice had nowhere to go.
class SaleCheckoutScreen extends ConsumerStatefulWidget {
  const SaleCheckoutScreen({super.key});

  @override
  ConsumerState<SaleCheckoutScreen> createState() => _SaleCheckoutScreenState();
}

class _SaleCheckoutScreenState extends ConsumerState<SaleCheckoutScreen> {
  Customer? _customer;
  String? _couponCode;
  bool _busy = false;

  /// Sale-level discount. Percent wins when set, matching the request builder.
  double _discountAmount = 0;
  double? _discountPercent;

  /// Extra charges (shipping, packaging, delivery, handling).
  final List<ChargeInput> _charges = [];

  // Owned by the screen, not by the sheets that use them: a controller disposed
  // right after `await showModalBottomSheet` is still being read while the route
  // animates out, which throws and paints the red screen.
  final TextEditingController _couponController = TextEditingController();
  final TextEditingController _discountController = TextEditingController();

  @override
  void dispose() {
    _couponController.dispose();
    _discountController.dispose();
    super.dispose();
  }

  CartController get _cart => ref.read(cartProvider(kCheckoutCart).notifier);

  // ------------------------------------------------------------- customer

  Future<void> _chooseCustomer({int mode = 0}) async {
    final chosen = await pickCustomer(context, ref, initialMode: mode);
    if (chosen == null || !mounted) return;
    setState(() => _customer = chosen);
  }

  // ------------------------------------------------------------- discount

  /// Sale-level discount, entered as rupees or a percentage.
  ///
  /// The figure shown here is what the app expects; the authoritative discount
  /// comes back on the created sale, which is why the receipt prints the server's
  /// own subtotal/discount/total rather than these numbers.
  Future<void> _editDiscount(double subtotal) async {
    var asPercent = _discountPercent != null;
    final controller = _discountController;
    controller.text = asPercent
        ? qty(_discountPercent!)
        : (_discountAmount > 0 ? _discountAmount.toStringAsFixed(2) : '');

    final applied = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final entered = double.tryParse(controller.text.trim()) ?? 0;
          final off = asPercent ? subtotal * (entered / 100) : entered;
          final capped = off > subtotal ? subtotal : off;

          return Padding(
            padding: EdgeInsets.fromLTRB(
              kScreenMargin,
              16,
              kScreenMargin,
              16 + MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Discount',
                    style: Theme.of(sheetContext).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 14),
                  // Labels only: SegmentedButton doesn't scroll or wrap, and
                  // icon+label segments overflow on a narrow phone.
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('₹ Amount')),
                      ButtonSegment(value: true, label: Text('% Percent')),
                    ],
                    selected: {asPercent},
                    showSelectedIcon: false,
                    onSelectionChanged: (values) =>
                        setSheetState(() => asPercent = values.first),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setSheetState(() {}),
                    decoration: InputDecoration(
                      prefixText: asPercent ? null : '₹ ',
                      suffixText: asPercent ? '%' : null,
                      labelText: asPercent ? 'Percent off' : 'Amount off',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DetailRow(label: 'Cart', value: money(subtotal)),
                  DetailRow(
                    label: 'Discount',
                    value: '− ${money(capped)}',
                    valueColor: kSuccess,
                  ),
                  const Divider(height: 18),
                  DetailRow(
                    label: 'Customer pays',
                    value: money(subtotal - capped),
                    emphasize: true,
                  ),
                  if (off > subtotal) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Capped at the cart total — a discount can\'t pay the '
                      'customer.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(sheetContext).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  FilledButton(
                    onPressed: () => Navigator.of(sheetContext).pop(true),
                    child: const Text('Apply'),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: () => Navigator.of(sheetContext).pop(false),
                    child: const Text('Remove discount'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    final entered = double.tryParse(controller.text.trim()) ?? 0;
    if (applied == null || !mounted) return;

    setState(() {
      if (applied != true || entered <= 0) {
        _discountAmount = 0;
        _discountPercent = null;
      } else if (asPercent) {
        _discountPercent = entered;
        _discountAmount = 0;
      } else {
        _discountAmount = entered > subtotal ? subtotal : entered;
        _discountPercent = null;
      }
    });
  }

  Future<void> _editCoupon() async {
    final controller = _couponController;
    controller.text = _couponCode ?? '';
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Coupon code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Code',
            helperText: 'The server applies and validates the discount.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(''),
            child: const Text('Remove'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Apply'),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    setState(() => _couponCode = result.isEmpty ? null : result);
  }

  Future<void> _addCharge() async {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final result = await showDialog<ChargeInput>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add Extra Charge'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Charge Name',
                hintText: 'e.g. Shipping, Delivery, Packaging',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                prefixText: '₹ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              final amt = double.tryParse(amountCtrl.text.trim()) ?? 0;
              if (name.isNotEmpty && amt > 0) {
                Navigator.of(dialogContext).pop(ChargeInput(name: name, amount: amt));
              }
            },
            child: const Text('Add Charge'),
          ),
        ],
      ),
    );
    if (result != null && mounted) {
      setState(() => _charges.add(result));
    }
  }

  // --------------------------------------------------------------- charge

  Future<void> _charge(List<CartLine> lines) async {
    final me = ref.read(meProvider);
    final warehouseId = me?.warehouseId;
    if (warehouseId == null) {
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'No store is assigned to this account, so a sale cannot be '
              'recorded. Ask an administrator to assign your store.',
        ),
      );
      return;
    }

    // The server requires a customer on every sale. The cashier picks who — the
    // app never chooses on their behalf, because a sale silently booked against
    // the wrong person is worse than a blocked Charge button.
    final customer = _customer;
    if (customer == null) {
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.validation,
          message: 'Choose a customer first — this server records one on every '
              'sale.',
        ),
      );
      return;
    }

    setState(() => _busy = true);
    final sales = ref.read(salesRepositoryProvider);
    // Captured before the awaits: reading `ref` after this screen is disposed
    // (forced sign-out mid-request) throws.
    final cart = _cart;

    try {
      final sale = await sales.create(
        warehouseId: warehouseId,
        customerId: customer.id,
        couponCode: _couponCode,
        discountAmount: _discountAmount,
        discountPercent: _discountPercent,
        charges: _charges.isEmpty ? null : _charges,
        items: lines.map((line) => line.toInput()).toList(),
      );

      // POS goes straight from DRAFT to CONFIRMED — confirming is what decrements
      // stock, so a till sale that stops at DRAFT is a bug, not a workflow.
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
      if (current.customerName == null || current.customerName!.isEmpty) {
        current = current.withCustomer(selectedCustomer);
      }

      cart.clear();
      if (!mounted) return;
      setState(() => _busy = false);

      if (confirmProblem == null) {
        _autoPrintReceiptOnce(current);
      }

      await _showReceiptSheet(current, confirmProblem);
      // Back to the till with an empty cart, ready for the next customer.
      if (mounted) Navigator.of(context).pop(true);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not record the sale.',
        ),
      );
    }
  }

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

    await showModalBottomSheet<void>(
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
                  color: problem == null ? kSuccess : scheme.error,
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
                // The server's own figures, not the till's estimate — this is
                // where a coupon or discount is confirmed as actually applied,
                // and where the real tax finally appears.
                DetailRow(label: 'Subtotal', value: money(sale.itemsSubtotal)),
                if (sale.discountTotal > 0)
                  DetailRow(
                    label: 'Discount',
                    value: '− ${money(sale.discountTotal)}',
                    valueColor: kSuccess,
                  ),
                if (sale.itemsTaxTotal > 0)
                  DetailRow(label: 'Tax', value: money(sale.itemsTaxTotal)),
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
                      Navigator.of(sheetContext).pop();
                      await _completeSale(sale.id);
                    },
                    icon: const Icon(Icons.task_alt_rounded),
                    label: const Text('Mark completed'),
                  ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    // Navigator captured from the sheet's own context: the sheet
                    // outlives this screen if the session expires behind it, and
                    // pushing from a dead context throws.
                    final navigator = Navigator.of(sheetContext);
                    navigator.pop();
                    navigator.push(
                      MaterialPageRoute(
                        builder: (_) => SaleDetailScreen(saleId: sale.id),
                      ),
                    );
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View invoice'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Next customer'),
                ),
              ],
            ),
          ),
        );
      },
    );
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
  Future<void> _autoPrintReceiptOnce(Sale sale) async {
    if (_autoPrintedSaleIds.contains(sale.id)) return;
    _autoPrintedSaleIds.add(sale.id);
    await _printReceipt(sale);
  }

  /// Prints [sale] to whichever Bluetooth thermal printer is paired,
  /// prompting the picker first if none has been chosen yet on this device.
  Future<void> _printReceipt(Sale sale) async {
    final me = ref.read(meProvider);
    final warehouseId = me?.warehouseId;
    if (me == null || warehouseId == null) return;

    try {
      final catalog = ref.read(catalogRepositoryProvider);

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
      } catch (_) {}
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
      if (!mounted) return;
      showErrorSnack(context, error);
    } catch (_) {
      if (!mounted) return;
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not print the receipt.',
        ),
      );
    }
  }

  // ----------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider(kCheckoutCart));
    final scheme = Theme.of(context).colorScheme;
    final unpriced = lines.any((line) => !line.isPriced);

    // Line discounts are already inside cartSubtotal; the sale-level one sits on
    // top of it.
    final gross = cartGross(lines);
    final lineDiscounts = cartLineDiscounts(lines);
    final subtotal = cartSubtotal(lines);
    final saleDiscount = _discountPercent != null
        ? subtotal * (_discountPercent! / 100)
        : _discountAmount;
    final cappedSaleDiscount = saleDiscount > subtotal ? subtotal : saleDiscount;
    final chargesTotal = _charges.fold<double>(0, (sum, c) => sum + c.amount);
    final payable = subtotal - cappedSaleDiscount + chargesTotal;

    return Scaffold(
      appBar: AppBar(title: const Text('Checkout')),
      body: lines.isEmpty
          ? const EmptyView(
              icon: Icons.shopping_bag_outlined,
              title: 'Nothing to charge for',
              message: 'Go back and tap the products the customer is buying.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                  kScreenMargin, kScreenMargin, kScreenMargin, 24),
              children: [
                _customerCard(scheme),
                const SizedBox(height: 10),
                SectionCard(
                  title: 'Items (${lines.length})',
                  child: Column(
                    children: [
                      for (final line in lines)
                        CartLineTile(
                          key: ValueKey('checkout-${line.product.id}'),
                          line: line,
                          onQuantityChanged: (value) =>
                              _cart.setQuantity(line.product.id, value),
                          onPriceChanged: (value) =>
                              _cart.setPrice(line.product.id, value),
                          onDiscountChanged: (value) =>
                              _cart.setDiscount(line.product.id, value),
                          onRemove: () => _cart.remove(line.product.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SectionCard(
                  title: 'Discount',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _editDiscount(subtotal),
                              icon: const Icon(Icons.percent_rounded, size: 18),
                              label: Text(
                                cappedSaleDiscount > 0
                                    ? 'Off ${money(cappedSaleDiscount)}'
                                    : 'Add discount',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _editCoupon,
                              icon: const Icon(Icons.local_offer_outlined,
                                  size: 18),
                              label: Text(
                                _couponCode ?? 'Coupon',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_couponCode != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Coupon $_couponCode is validated and priced by the '
                          'server — the amount it takes off appears on the '
                          'receipt.',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SectionCard(
                  title: 'Extra Charges (${_charges.length})',
                  trailing: TextButton.icon(
                    onPressed: _addCharge,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Charge'),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_charges.isEmpty)
                        Text(
                          'No extra charges (e.g. shipping, handling, packaging).',
                          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                        )
                      else
                        for (int i = 0; i < _charges.length; i++)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _charges[i].name,
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                Text(
                                  money(_charges[i].amount),
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => setState(() => _charges.removeAt(i)),
                                  icon: const Icon(Icons.close_rounded, size: 18),
                                ),
                              ],
                            ),
                          ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _invoiceCard(
                  scheme: scheme,
                  gross: gross,
                  lineDiscounts: lineDiscounts,
                  saleDiscount: cappedSaleDiscount,
                  chargesTotal: chargesTotal,
                  subtotal: subtotal,
                  payable: payable,
                ),
              ],
            ),
      bottomNavigationBar: lines.isEmpty
          ? null
          : CartSummaryBar(
              lines: lines,
              busy: _busy,
              total: payable,
              blocker: _customer == null
                  ? 'Choose a customer to charge'
                  : unpriced
                      ? 'Every line needs a price'
                      : null,
              actionLabel: 'Charge',
              onAction: () => _charge(lines),
              // The cart is already on this screen, so the chevron scrolls
              // nowhere useful — it re-opens the sheet for a quick edit.
              onEdit: () => showCartSheet(
                context: context,
                lines: lines,
                onQuantityChanged: (line, value) =>
                    _cart.setQuantity(line.product.id, value),
                onPriceChanged: (line, value) =>
                    _cart.setPrice(line.product.id, value),
                onDiscountChanged: (line, value) =>
                    _cart.setDiscount(line.product.id, value),
                onRemove: (line) => _cart.remove(line.product.id),
              ),
            ),
    );
  }

  Widget _customerCard(ColorScheme scheme) {
    final customer = _customer;
    final missing = customer == null;

    return SectionCard(
      title: 'Customer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: missing
                      ? scheme.errorContainer
                      : scheme.primaryContainer,
                  shape: BoxShape.circle,
                ),
                child: missing
                    ? Icon(Icons.person_search_rounded,
                        size: 20, color: scheme.onErrorContainer)
                    : Text(
                        initials(customer.name),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer?.name ?? 'No customer chosen',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: missing ? scheme.error : null,
                          ),
                    ),
                    Text(
                      missing
                          ? 'Required on every sale'
                          : (customer.subtitle.isEmpty
                              ? 'No phone or email on file'
                              : customer.subtitle),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (!missing)
                IconButton(
                  tooltip: 'Clear customer',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _customer = null),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _chooseCustomer(mode: 0),
                  icon: const Icon(Icons.person_search_rounded, size: 18),
                  label: Text(missing ? 'Select Existing' : 'Change Customer'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _chooseCustomer(mode: 1),
                  icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                  label: const Text('New Customer'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Search by name, phone or email, or add a new customer inline.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  /// The bill, itemised.
  Widget _invoiceCard({
    required ColorScheme scheme,
    required double gross,
    required double lineDiscounts,
    required double saleDiscount,
    required double chargesTotal,
    required double subtotal,
    required double payable,
  }) {
    return SectionCard(
      title: 'Invoice',
      child: Column(
        children: [
          DetailRow(label: 'Gross', value: money(gross)),
          if (lineDiscounts > 0)
            DetailRow(
              label: 'Line discounts',
              value: '− ${money(lineDiscounts)}',
              valueColor: kSuccess,
            ),
          if (saleDiscount > 0)
            DetailRow(
              label: _discountPercent != null
                  ? 'Sale discount (${qty(_discountPercent)}%)'
                  : 'Sale discount',
              value: '− ${money(saleDiscount)}',
              valueColor: kSuccess,
            ),
          if (chargesTotal > 0)
            DetailRow(
              label: 'Extra Charges',
              value: money(chargesTotal),
            ),
          if (lineDiscounts > 0 || saleDiscount > 0 || chargesTotal > 0) ...[
            const Divider(height: 18),
            DetailRow(label: 'Subtotal', value: money(payable)),
          ],
          if (_couponCode != null)
            DetailRow(label: 'Coupon $_couponCode', value: 'Priced by server'),
          DetailRow(label: 'Tax', value: 'Added by the server'),
          const Divider(height: 18),
          DetailRow(
            label: 'Customer pays',
            value: money(payable),
            emphasize: true,
          ),
          const SizedBox(height: 4),
          Text(
            'Tax and any coupon are calculated when the sale is recorded, so the '
            'final total on the receipt can differ from this figure.',
            style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
