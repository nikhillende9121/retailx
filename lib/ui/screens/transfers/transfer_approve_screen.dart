import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/inventory.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/cart_panel.dart' show ProductThumb;
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';

/// Approves a DRAFT transfer request: picks which store it ships from and
/// how much of each line is actually approved, line by line.
///
/// `POST /stock-transfers/{id}/approve` is what sets `fromWarehouseId` at
/// all — a transfer is created with only a destination, so this is the one
/// place the source store gets chosen (see `Docs/business-rules/
/// stock-transfer.md`). Approved quantity is what `/ship` is capped at, and
/// it can be less than requested — the requester doesn't always get
/// everything they asked for.
class TransferApproveScreen extends ConsumerStatefulWidget {
  const TransferApproveScreen({super.key, required this.transferId});

  final String transferId;

  @override
  ConsumerState<TransferApproveScreen> createState() =>
      _TransferApproveScreenState();
}

class _TransferApproveScreenState
    extends ConsumerState<TransferApproveScreen> {
  final Map<String, double> _quantities = {};
  Warehouse? _fromWarehouse;
  bool _busy = false;

  Future<void> _chooseFromWarehouse(StockTransfer transfer) async {
    final catalog = ref.read(catalogRepositoryProvider);
    try {
      final all = await catalog.warehouses();
      // Can't ship a transfer from the same store it's going to.
      final options =
          all.where((w) => w.id != transfer.toWarehouseId).toList();
      if (!mounted) return;
      final picked = await pickWarehouse(
        context,
        options,
        title: 'Choose the source store',
      );
      if (picked != null) setState(() => _fromWarehouse = picked);
    } on AppError catch (error) {
      if (mounted) showErrorSnack(context, error);
    }
  }

  Future<void> _submit(StockTransfer transfer) async {
    final fromWarehouse = _fromWarehouse;
    if (fromWarehouse == null) return;
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
      await ref.read(inventoryRepositoryProvider).approveTransfer(
            transfer.id,
            fromWarehouseId: fromWarehouse.id,
            items: items,
          );
      if (!mounted) return;
      showInfoSnack(context, 'Transfer approved.');
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
          message: 'Could not approve this transfer.',
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
      appBar: AppBar(title: const Text('Approve transfer')),
      body: AsyncView<StockTransfer>(
        load: () async {
          var transfer = await inventory.transfer(widget.transferId);

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

          // Defaults each line to "approve everything requested" — the
          // common case — without clobbering an in-progress edit on refresh.
          for (final item in transfer.items) {
            _quantities.putIfAbsent(item.id, () => item.quantity);
          }
          return transfer;
        },
        builder: (context, transfer, reload) {
          final totalUnits =
              _quantities.values.fold<double>(0, (sum, v) => sum + v);
          final fromWarehouse = _fromWarehouse;

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
                            'To ${transfer.toLabel()}',
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
                      title: 'Source store',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _chooseFromWarehouse(transfer),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(
                                Icons.store_mall_directory_outlined,
                                color: fromWarehouse == null
                                    ? scheme.error
                                    : scheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  fromWarehouse?.name ??
                                      'Choose which store ships this',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: fromWarehouse == null
                                        ? scheme.error
                                        : null,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right_rounded,
                                  color: scheme.onSurfaceVariant),
                            ],
                          ),
                        ),
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
                                        Text(
                                          'Requested ${qty(item.quantity)}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: scheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  QuantityStepper(
                                    value: _quantities[item.id] ?? 0,
                                    min: 0,
                                    max: item.quantity,
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
                    onPressed: (fromWarehouse == null ||
                            totalUnits <= 0 ||
                            _busy)
                        ? null
                        : () => _submit(transfer),
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline_rounded),
                    label: Text(
                      _busy
                          ? 'Working…'
                          : fromWarehouse == null
                              ? 'Choose the source store first'
                              : 'Approve (${qty(totalUnits)} unit'
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
