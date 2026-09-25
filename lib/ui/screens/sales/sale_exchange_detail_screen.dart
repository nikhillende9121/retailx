import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'sale_detail_screen.dart';
import 'sale_exchanges_screen.dart' show differenceStyle;

/// A single recorded exchange — read-only, reached by tapping a tile on the
/// Exchanges list. Like a return, the settlement is final once recorded.
///
/// `GET /sale-exchanges/:id` nests two full sub-objects rather than a flat
/// shape — [SaleExchange.saleReturn] (what came back) and
/// [SaleExchange.newSale] (the replacement sale, with its own items, tax,
/// discounts and charges) — so this screen shows both in full, the same
/// depth [SaleDetailScreen] shows for an ordinary sale.
class SaleExchangeDetailScreen extends ConsumerWidget {
  const SaleExchangeDetailScreen({super.key, required this.exchangeId});

  final String exchangeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.read(salesRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Exchange')),
      body: AsyncView<SaleExchange>(
        load: () async {
          var exchange = await sales.getExchange(exchangeId);
          final catalog = ref.read(catalogRepositoryProvider);

          if (exchange.newSale.needsCustomerLookup) {
            try {
              final customer =
                  await catalog.customer(exchange.newSale.customerId!);
              if (customer != null) exchange = exchange.withCustomer(customer);
            } on AppError {
              // No permission to read customers, or it's gone — the id still
              // shows.
            }
          }

          if (exchange.newSale.needsWarehouseLookup) {
            try {
              final warehouse =
                  await catalog.warehouse(exchange.newSale.warehouseId!);
              if (warehouse != null) {
                exchange = exchange.withWarehouseName(warehouse.name);
              }
            } on AppError {
              // No permission to read warehouses — the id still shows.
            }
          }

          if (exchange.needsItemProductLookup) {
            final ids = [
              ...exchange.returnItems.map((item) => item.productId ?? ''),
              ...exchange.newItems.map((item) => item.productId),
            ];
            final names = await resolveProductNames(catalog, ids);
            if (names.isNotEmpty) {
              exchange = exchange.withItems(
                returnItems: [
                  for (final item in exchange.returnItems)
                    if (names[item.productId] case final name?)
                      item.withProductName(name)
                    else
                      item,
                ],
                newItems: [
                  for (final item in exchange.newItems)
                    if (names[item.productId] case final name?)
                      item.withProductName(name)
                    else
                      item,
                ],
              );
            }
          }

          return exchange;
        },
        builder: (context, exchange, reload) =>
            _ExchangeBody(exchange: exchange),
      ),
    );
  }
}

class _ExchangeBody extends StatelessWidget {
  const _ExchangeBody({required this.exchange});

  final SaleExchange exchange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = differenceStyle(context, exchange);
    final newSale = exchange.newSale;
    final saleReturn = exchange.saleReturn;
    final refundValue = saleReturn.computedRefund;
    final newItemsTotal = newSale.computedTotal;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(exchange.label, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              DetailRow(
                label: 'Date',
                value: prettyDateTime(exchange.createdAt),
              ),
              DetailRow(label: 'Customer', value: newSale.customerLabel),
              DetailRow(
                label: 'Store',
                value: newSale.warehouseName ??
                    (newSale.warehouseId != null
                        ? 'Store #${newSale.warehouseId}'
                        : '—'),
              ),
              if ((exchange.reason ?? '').isNotEmpty)
                DetailRow(label: 'Reason', value: exchange.reason!),
              const SizedBox(height: 4),
              if (exchange.saleId != null)
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SaleDetailScreen(saleId: exchange.saleId!),
                    ),
                  ),
                  icon: const Icon(Icons.receipt_long_outlined, size: 18),
                  label: Text('View original sale #${exchange.saleId}'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Returned (${exchange.returnItems.length})',
          child: Column(
            children: [
              if (exchange.returnItems.isEmpty)
                Text(
                  'Nothing was returned in this exchange.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              for (final item in exchange.returnItems)
                _ItemLine(
                  name: item.productName,
                  detail: '${qty(item.quantity)} returned',
                  amount: '− ${money(item.refundAmount ?? 0)}',
                  amountColor: scheme.error,
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'New items (${newSale.items.length})',
          child: Column(
            children: [
              if (newSale.items.isEmpty)
                Text(
                  'No replacement items in this exchange.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              for (final item in newSale.items) ...[
                if (item != newSale.items.first)
                  Divider(height: 1, color: scheme.outlineVariant),
                _ItemLine(
                  name: item.productName,
                  detail: '${qty(item.quantity)} × ${money(item.price)}'
                      '${item.taxes.isNotEmpty ? ' · ${item.taxes.map((t) => '${t.component} ${qty(t.ratePercent)}%').join(' + ')}' : ''}',
                  amount: money(item.amountWithTax),
                  amountSubtext: item.tax > 0 ? '+ ${money(item.tax)} tax' : null,
                ),
              ],
            ],
          ),
        ),
        if (newSale.discounts.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            title: 'Discounts on new items (${newSale.discounts.length})',
            child: Column(
              children: [
                for (final discount in newSale.discounts)
                  DetailRow(
                    label: discount.isCoupon
                        ? 'Coupon #${discount.couponId}'
                        : discount.isLineLevel
                            ? 'Line discount #${discount.discountId ?? discount.id}'
                            : 'Order discount #${discount.discountId ?? discount.id}',
                    value: '− ${money(discount.amount)}',
                    valueColor: successColor(scheme.brightness),
                  ),
              ],
            ),
          ),
        ],
        if (newSale.charges.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            title: 'Charges on new items (${newSale.charges.length})',
            child: Column(
              children: [
                for (final charge in newSale.charges)
                  DetailRow(
                    label: charge.name,
                    value: charge.taxAmount > 0
                        ? '${money(charge.amount)} + ${money(charge.taxAmount)} tax'
                        : money(charge.amount),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        SectionCard(
          title: 'New items total',
          child: Column(
            children: [
              DetailRow(label: 'Subtotal', value: money(newSale.itemsSubtotal)),
              if (newSale.discountTotal > 0)
                DetailRow(
                  label: 'Discount',
                  value: '− ${money(newSale.discountTotal)}',
                  valueColor: successColor(scheme.brightness),
                ),
              if (newSale.chargesTotal > 0)
                DetailRow(label: 'Charges', value: money(newSale.chargesTotal)),
              if (newSale.itemsTaxTotal + newSale.chargesTaxTotal > 0)
                DetailRow(
                  label: 'Tax',
                  value: money(newSale.itemsTaxTotal + newSale.chargesTaxTotal),
                ),
              const Divider(height: 18),
              DetailRow(
                label: 'Total',
                value: money(newItemsTotal),
                emphasize: true,
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
                label: 'Returned value',
                value: '− ${money(refundValue)}',
                valueColor: successColor(scheme.brightness),
              ),
              DetailRow(label: 'New items total', value: money(newItemsTotal)),
              const Divider(height: 18),
              Row(
                children: [
                  Icon(style.icon, size: 18, color: style.color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      style.label,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: style.color,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ItemLine extends StatelessWidget {
  const _ItemLine({
    required this.name,
    required this.detail,
    required this.amount,
    this.amountColor,
    this.amountSubtext,
  });

  final String name;
  final String detail;
  final String amount;
  final Color? amountColor;
  final String? amountSubtext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  detail,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(fontWeight: FontWeight.w600, color: amountColor),
              ),
              if (amountSubtext != null)
                Text(
                  amountSubtext!,
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
