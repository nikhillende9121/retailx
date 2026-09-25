import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/inventory.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/cart_panel.dart' show ProductThumb;
import '../../widgets/common.dart';

/// Book an inbound transfer's shipped stock into this store, line by line.
///
/// `POST /stock-transfers/{id}/receive` takes a `receivedQuantity` per line,
/// capped at what was actually shipped — not always the same (breakage, a
/// miscount at the source) — so this is a real per-item form, not a single
/// yes/no confirm.
class TransferReceiveScreen extends ConsumerStatefulWidget {
  const TransferReceiveScreen({super.key, required this.transferId});

  final String transferId;

  @override
  ConsumerState<TransferReceiveScreen> createState() =>
      _TransferReceiveScreenState();
}

class _TransferReceiveScreenState extends ConsumerState<TransferReceiveScreen> {
  final Map<String, double> _quantities = {};
  bool _busy = false;

  Future<void> _submit(StockTransfer transfer) async {
    final items = [
      for (final item in transfer.items)
        if ((_quantities[item.id] ?? 0) > 0)
          TransferStageInput(
            stockTransferItemId: item.id,
            quantity: _quantities[item.id]!,
          ),
    ];
    if (items.isEmpty) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(inventoryRepositoryProvider)
          .receiveTransfer(transfer.id, items);
      if (!mounted) return;
      showInfoSnack(context, 'Stock received into this store.');
      Navigator.of(context).pop(true);
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
          message: 'Could not receive this transfer.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final inventory = ref.read(inventoryRepositoryProvider);
    final catalog = ref.read(catalogRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Receive transfer')),
      body: AsyncView<StockTransfer>(
        load: () async {
          var transfer = await inventory.transfer(widget.transferId);

          // `/stock-transfers` never expands the product relation, so every
          // line arrives as an id and a generic placeholder name.
          if (transfer.needsItemProductLookup) {
            final products = await resolveProducts(
              catalog,
              transfer.items
                  .where((item) => item.needsProductLookup)
                  .map((item) => item.productId),
            );
            if (products.isNotEmpty) {
              transfer = transfer.withItems([
                for (final item in transfer.items)
                  if (products[item.productId] case final product?)
                    item.withProduct(product)
                  else
                    item,
              ]);
            }
          }

          // Defaults each line to "receive everything that shipped" — the
          // common case — without clobbering an in-progress edit on refresh.
          for (final item in transfer.items) {
            _quantities.putIfAbsent(
              item.id,
              () => item.shippedQuantity ?? item.quantity,
            );
          }
          return transfer;
        },
        builder: (context, transfer, reload) {
          final totalUnits =
              _quantities.values.fold<double>(0, (sum, v) => sum + v);

          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                  children: [
                    AppCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transfer.label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'From ${transfer.fromLabel()}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SectionCard(
                      title: 'Items (${transfer.items.length})',
                      child: Column(
                        children: [
                          for (final item in transfer.items)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  ProductThumb(
                                    name: item.productName,
                                    imageUrl: item.imageUrl,
                                    size: 48,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.productName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w600),
                                        ),
                                        if (item.sku != null)
                                          Text(
                                            item.sku!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: scheme.onSurfaceVariant,
                                            ),
                                          ),
                                        const SizedBox(height: 2),
                                        // Full chain, not just "Shipped" —
                                        // what got approved matters here too:
                                        // it's the ceiling shippedQuantity
                                        // itself was capped at.
                                        Wrap(
                                          spacing: 8,
                                          children: [
                                            for (final (label, value)
                                                in item.quantityStages)
                                              Text(
                                                '$label ${qty(value)}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight:
                                                      label == 'Shipped'
                                                          ? FontWeight.w700
                                                          : FontWeight.w400,
                                                  color: label == 'Shipped'
                                                      ? scheme.onSurface
                                                      : scheme
                                                          .onSurfaceVariant,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  QuantityStepper(
                                    value: _quantities[item.id] ?? 0,
                                    min: 0,
                                    max: item.shippedQuantity ?? item.quantity,
                                    editable: true,
                                    onChanged: (value) => setState(
                                        () => _quantities[item.id] = value),
                                  ),
                                ],
                              ),
                            ),
                        ],
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
                    onPressed: (totalUnits <= 0 || _busy)
                        ? null
                        : () => _submit(transfer),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.inventory_rounded),
                    label: Text(
                      _busy
                          ? 'Working…'
                          : 'Receive (${qty(totalUnits)} unit'
                              '${totalUnits == 1 ? '' : 's'})',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
