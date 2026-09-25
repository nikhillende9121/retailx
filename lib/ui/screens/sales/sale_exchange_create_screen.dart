import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../state/cart.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/cart_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import 'sale_exchanges_screen.dart' show differenceStyle;

/// Take items back and sell replacements in one transaction: the return picker
/// from Sale Returns on top, a mini till for the replacements underneath, and
/// the settlement method at the bottom.
class SaleExchangeCreateScreen extends ConsumerStatefulWidget {
  const SaleExchangeCreateScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SaleExchangeCreateScreen> createState() =>
      _SaleExchangeCreateScreenState();
}

class _SaleExchangeCreateScreenState
    extends ConsumerState<SaleExchangeCreateScreen> {
  final Map<String, double> _returnQuantities = {};
  final Map<String, double> _returnUnitPrices = {};
  final TextEditingController _reason = TextEditingController();
  String _paymentMethod = kPaymentMethods.first;
  bool _busy = false;
  String? _reasonError;

  CartController get _cart => ref.read(cartProvider(kExchangeCart).notifier);

  @override
  void initState() {
    super.initState();
    // A stale replacement cart from a previous exchange must not leak in.
    Future.microtask(_cart.clear);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _hasReturns => _returnQuantities.values.any((value) => value > 0);

  /// Indicative only — the server computes the real settlement.
  double get _estimatedReturnValue {
    var total = 0.0;
    _returnQuantities.forEach((saleItemId, quantity) {
      total += quantity * (_returnUnitPrices[saleItemId] ?? 0);
    });
    return total;
  }

  /// Adds [product] with its real, price-list-resolved price — `GET
  /// /products` (what the picker calls) carries no price field at all, so
  /// [Product.defaultPrice] is always null coming from there and the line
  /// would otherwise silently start at ₹0. Best-effort: a product with no
  /// price configured for this warehouse still gets added (so the cashier
  /// isn't blocked), just at ₹0 with a snack explaining why.
  Future<void> _addReplacement(Sale sale) async {
    // Resolved before the awaits — `_submit` does the same, for the same
    // reason: `ref` is unusable once this screen is disposed, and the
    // picker/network call outlive it.
    final cart = _cart;
    final pricing = ref.read(pricingRepositoryProvider);
    final warehouseId = ref.read(warehouseIdProvider);

    final product = await pickProduct(context, ref, title: 'Replacement product');
    if (product == null || !mounted) return;

    double price = 0;
    if (warehouseId != null) {
      try {
        price = await pricing.resolvePrice(
          productId: product.id,
          warehouseId: warehouseId,
          customerId: sale.customerId,
        );
      } on AppError catch (error) {
        if (mounted) {
          showErrorSnack(
            context,
            AppError(
              code: error.code,
              message: 'No price configured for ${product.name}: '
                  '${error.uiMessage}',
            ),
          );
        }
      } catch (_) {
        // Best-effort — see doc comment above.
      }
    }
    if (!mounted) return;
    cart.add(product);
    cart.setPrice(product.id, price);
  }

  Future<void> _submit(Sale sale, List<CartLine> lines) async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _reasonError = 'A reason is required');
      return;
    }
    setState(() {
      _reasonError = null;
      _busy = true;
    });

    // Captured before the awaits — reading `ref` after a dispose throws.
    final cart = _cart;
    final returnItems = <ReturnLineInput>[];
    _returnQuantities.forEach((saleItemId, quantity) {
      if (quantity > 0) {
        returnItems
            .add(ReturnLineInput(saleItemId: saleItemId, quantity: quantity));
      }
    });

    try {
      final result = await ref.read(salesRepositoryProvider).createExchange(
            saleId: sale.id,
            reason: reason,
            returnItems: returnItems,
            newItems: lines.map((line) => line.toInput()).toList(),
            paymentMethod: _paymentMethod,
          );
      cart.clear();
      if (!mounted) return;
      setState(() => _busy = false);
      await _showSettlementSheet(result);
      if (mounted) Navigator.of(context).pop(true);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error.isValidation) _reasonError = error.fieldErrors['reason'];
      });
      showErrorSnack(context, error);
    } catch (_) {
      // Anything unexpected must still release the button, or the screen is
      // stuck behind a spinner.
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not record the exchange.',
        ),
      );
    }
  }

  /// The settlement is the whole point of an exchange, so it gets a full sheet
  /// rather than a snackbar.
  Future<void> _showSettlementSheet(SaleExchange result) async {
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isDismissible: false,
      builder: (sheetContext) {
        final style = differenceStyle(sheetContext, result);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(style.icon, size: 40, color: style.color),
                const SizedBox(height: 10),
                Text(
                  style.label,
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(color: style.color, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  // The response has no paymentMethod field — this is
                  // literally what was just submitted to create it.
                  '${result.label} · settled by ${humanizeCode(_paymentMethod)}',
                  textAlign: TextAlign.center,
                  style: Theme.of(sheetContext).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                for (final item in result.returnItems)
                  DetailRow(
                    label: 'Back: ${item.productName} × ${qty(item.quantity)}',
                    value: money(item.refundAmount),
                  ),
                for (final item in result.newItems)
                  DetailRow(
                    label: 'Out: ${item.productName} × ${qty(item.quantity)}',
                    value: money(item.amount),
                  ),
                const SizedBox(height: 18),
                FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The sale, plus the sold products' images (looked up separately — a
  /// sale line only ever carries a productId/name, never an image) so
  /// "Coming back" shows what's actually being handed back, not just text.
  /// Best-effort like `resolveProductNames` elsewhere: a product that 404s
  /// or is out of the caller's permission just keeps no thumbnail.
  Future<(Sale, Map<String, Product>)> _load() async {
    final sale = await ref.read(salesRepositoryProvider).get(widget.saleId);
    final products = await resolveProducts(
      ref.read(catalogRepositoryProvider),
      sale.items.map((item) => item.productId),
    );
    return (sale, products);
  }

  @override
  Widget build(BuildContext context) {
    // Watched here rather than inside AsyncView's builder: a `ref.watch` in a
    // descendant's build phase doesn't register a lasting dependency.
    final lines = ref.watch(cartProvider(kExchangeCart));

    return Scaffold(
      appBar: AppBar(title: const Text('New exchange')),
      body: AsyncView<(Sale, Map<String, Product>)>(
        load: _load,
        builder: (context, data, reload) =>
            _buildForm(context, data.$1, data.$2, lines),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Sale sale,
      Map<String, Product> soldProducts, List<CartLine> lines) {
    final scheme = Theme.of(context).colorScheme;
    final returnable =
        sale.items.where((item) => item.availableToReturn > 0).toList();
    final replacementTotal = cartSubtotal(lines);
    final estimate = replacementTotal - _estimatedReturnValue;

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              AppCard(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(sale.label,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                          Text(
                            '${prettyDate(sale.saleDate ?? sale.createdAt)} · '
                            '${sale.customerLabel}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(money(sale.computedTotal),
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                title: 'Coming back',
                child: Column(
                  children: [
                    if (returnable.isEmpty)
                      Text(
                        'Every line on this sale has already been returned.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    for (final item in returnable)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            ProductThumb(
                              name: item.productName,
                              imageUrl: soldProducts[item.productId]?.imageUrl,
                              size: 40,
                              radius: 8,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'sold ${qty(item.quantity)} × ${money(item.price)}'
                                    ' · up to ${qty(item.availableToReturn)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            QuantityStepper(
                              value: _returnQuantities[item.id] ?? 0,
                              min: 0,
                              max: item.availableToReturn,
                              onChanged: (value) => setState(() {
                                if (value <= 0) {
                                  _returnQuantities.remove(item.id);
                                  _returnUnitPrices.remove(item.id);
                                } else {
                                  _returnQuantities[item.id] = value;
                                  _returnUnitPrices[item.id] = item.price;
                                }
                              }),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                title: 'Going out',
                trailing: TextButton.icon(
                  onPressed: () => _addReplacement(sale),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add'),
                ),
                child: Column(
                  children: [
                    if (lines.isEmpty)
                      Text(
                        'Add the replacement products the customer is leaving with.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    for (final line in lines)
                      CartLineTile(
                        key: ValueKey('exchange-${line.product.id}'),
                        line: line,
                        onQuantityChanged: (value) =>
                            _cart.setQuantity(line.product.id, value),
                        // No onPriceChanged: the server resolves this
                        // item's price itself and ignores whatever's sent
                        // (see sale-exchange.schema.ts's newItems) — shown
                        // read-only instead of inviting an edit that would
                        // silently do nothing.
                        onRemove: () => _cart.remove(line.product.id),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                title: 'Settlement',
                child: Column(
                  children: [
                    DetailRow(
                      label: 'Replacements',
                      value: money(replacementTotal),
                    ),
                    DetailRow(
                      label: 'Returning (at sold price)',
                      value: '− ${money(_estimatedReturnValue)}',
                    ),
                    const Divider(height: 18),
                    DetailRow(
                      label: estimate >= 0
                          ? 'Estimated to collect'
                          : 'Estimated to refund',
                      value: money(estimate.abs()),
                      emphasize: true,
                      // Owing more isn't a decline and a refund isn't an
                      // error — neither borrows the brand blue or the
                      // reserved error red; see differenceStyle in
                      // sale_exchanges_screen.dart for the settled version of
                      // this same distinction.
                      valueColor: estimate >= 0
                          ? scheme.onSurface
                          : successColor(scheme.brightness),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Estimate only — the server applies the original '
                      "sale's discounts and returns the exact difference.",
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Settle by',
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Chips rather than a dropdown: four options, one tap each,
                    // and no dependence on a version-shifting dropdown API.
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final method in kPaymentMethods)
                          ChoiceChip(
                            label: Text(humanizeCode(method)),
                            selected: _paymentMethod == method,
                            onSelected: (_) =>
                                setState(() => _paymentMethod = method),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                title: 'Reason',
                child: TextField(
                  controller: _reason,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'e.g. wrong size, swapping colour',
                    errorText: _reasonError,
                  ),
                ),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: FilledButton.icon(
              // No price gate: the server resolves the replacement items'
              // price itself (see CartLineTile.onPriceChanged's doc comment)
              // and ignores whatever the client sends, so there's nothing
              // meaningful to validate about it here.
              onPressed: (!_hasReturns || lines.isEmpty || _busy)
                  ? null
                  : () => _submit(sale, lines),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.swap_horiz_rounded),
              label: Text(_busy ? 'Working…' : 'Record exchange'),
            ),
          ),
        ),
      ],
    );
  }
}
