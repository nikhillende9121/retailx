import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/models/inventory.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../state/cart.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/cart_panel.dart';
import '../../widgets/common.dart';
import 'barcode_scan_screen.dart';
import 'sale_invoice_screen.dart';

/// The till. Tap products, adjust quantities, then proceed to Checkout.
///
/// Customer details and payment happen on the next screen so this one stays
/// fast and uncluttered — it is the surface the cashier looks at for every
/// single item in every single transaction.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  String _query = '';
  int _reload = 0;
  _StockFilter _filter = _StockFilter.all;

  CartController get _cart => ref.read(cartProvider(kCheckoutCart).notifier);

  /// Scans a barcode and either adds the single matching product straight to
  /// the cart, or filters the grid down to it so the cashier can tap it.
  Future<void> _scanBarcode() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScanScreen()),
    );
    if (code == null || code.isEmpty || !mounted) return;

    final inventory = ref.read(inventoryRepositoryProvider);
    final page = await inventory.balance(
      search: code,
      pageSize: 50,
      warehouseId: ref.read(warehouseIdProvider),
    );
    final matches =
        page.items.where((balance) => balance.matches(code)).toList();
    if (!mounted) return;

    if (matches.length == 1) {
      final balance = matches.single;
      if (!balance.inStock) {
        showInfoSnack(context, '${balance.productName} is out of stock.');
        return;
      }
      _cart.add(balance.product);
      showInfoSnack(context, 'Added ${balance.productName}.');
      return;
    }

    setState(() => _query = code);
    if (matches.isEmpty) {
      showInfoSnack(context, 'No product matches "$code".');
    }
  }

  Widget _filterChips(BuildContext context) {
    const filters = <_StockFilter, String>{
      _StockFilter.all: 'All',
      _StockFilter.inStock: 'In stock',
      _StockFilter.low: 'Low stock',
    };
    final scheme = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: kScreenMargin),
      child: Row(
        children: [
          for (final entry in filters.entries)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: _filter == entry.key,
                onSelected: (_) => setState(() => _filter = entry.key),
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: _filter == entry.key
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, InventoryRepository inventory) {
    return AsyncView<List<StockBalance>>(
      reloadToken: '$_query|$_reload',
      load: () async {
        final page = await inventory.balance(
          search: _query,
          pageSize: 100,
          warehouseId: ref.read(warehouseIdProvider),
        );
        return page.items;
      },
      builder: (context, balances, reload) {
        final filtered = balances.where((balance) {
          if (!balance.matches(_query)) return false;
          switch (_filter) {
            case _StockFilter.all:
              return true;
            case _StockFilter.inStock:
              return balance.inStock;
            case _StockFilter.low:
              return balance.quantity > 0 && balance.quantity <= 5;
          }
        }).toList();

        if (filtered.isEmpty) {
          return ListView(
            children: [
              SizedBox(
                height: 320,
                child: EmptyView(
                  icon: Icons.grid_view_rounded,
                  title: _query.isEmpty
                      ? 'Nothing to show here'
                      : 'Nothing matches "$_query"',
                  message: _query.isEmpty
                      ? 'Receive a purchase or a transfer to put stock on the '
                          'shelves, or switch the filter to All.'
                      : 'Try a different name, SKU or barcode.',
                ),
              ),
            ],
          );
        }

        final cartLines = ref.watch(cartProvider(kCheckoutCart));

        return ProductGrid(
          padding: const EdgeInsets.fromLTRB(
              kScreenMargin, kScreenMargin, kScreenMargin, 76),
          children: [
            for (final balance in filtered)
              ProductTile(
                product: balance.product,
                stock: balance.quantity,
                inCart: cartLines
                    .where((line) => line.product.id == balance.productId)
                    .fold<double>(0, (sum, line) => sum + line.quantity),
                onTap: balance.inStock
                    ? () => _cart.add(balance.product)
                    : null,
                onAdd: balance.inStock
                    ? () => _cart.add(balance.product)
                    : null,
                onRemove: () => _cart.decrement(balance.productId),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final lines = ref.watch(cartProvider(kCheckoutCart));
    final inventory = ref.read(inventoryRepositoryProvider);
    final unpriced = lines.any((line) => !line.isPriced);
    final subtotal = cartSubtotal(lines);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
              kScreenMargin, 8, kScreenMargin, 8),
          child: SearchBox(
            hint: 'Search products, SKUs…',
            onChanged: (value) => setState(() => _query = value),
            trailing: IconButton(
              tooltip: 'Scan a barcode',
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: _scanBarcode,
            ),
          ),
        ),
        _filterChips(context),
        const SizedBox(height: 2),
        Expanded(child: _grid(context, inventory)),
        CartSummaryBar(
          lines: lines,
          busy: false,
          blocker: lines.isEmpty
              ? null
              : unpriced
                  ? 'Every line needs a price'
                  : null,
          total: subtotal,
          actionLabel: 'Checkout',
          onAction: lines.isEmpty || unpriced
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SaleInvoiceScreen(),
                    ),
                  ),
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
      ],
    );
  }
}

enum _StockFilter { all, inStock, low }
