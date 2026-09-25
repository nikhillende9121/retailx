import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/catalog.dart';
import '../../../data/repositories/inventory_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';

/// Request stock into this store.
///
/// `POST /stock-transfers` only ever takes a destination (`toWarehouseId`) —
/// the source warehouse isn't chosen until a tenant admin approves the
/// request. So this store's own id is the only warehouse this screen deals
/// with, and it's sent from code rather than asked of the user.
class TransferCreateScreen extends ConsumerStatefulWidget {
  const TransferCreateScreen({super.key});

  @override
  ConsumerState<TransferCreateScreen> createState() =>
      _TransferCreateScreenState();
}

class _TransferLine {
  _TransferLine({required this.product, required this.quantity});

  final Product product;
  double quantity;
}

class _TransferCreateScreenState extends ConsumerState<TransferCreateScreen> {
  final List<_TransferLine> _lines = [];
  DateTime _date = DateTime.now();
  bool _busy = false;

  Future<void> _addLine() async {
    // A transfer moves existing stock between warehouses — nothing to do
    // with retail pricing at either end — so it must not be filtered down
    // to only products price-listed for this warehouse the way choosing
    // what to sell would be (see `pickProduct`'s `includeUnpricedProducts`).
    final product = await pickProduct(
      context,
      ref,
      title: 'Add a product',
      includeUnpricedProducts: true,
    );
    if (product == null || !mounted) return;
    setState(() {
      final index =
          _lines.indexWhere((line) => line.product.id == product.id);
      if (index >= 0) {
        _lines[index].quantity += 1;
      } else {
        _lines.add(_TransferLine(product: product, quantity: 1));
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _submit(String myWarehouseId) async {
    setState(() => _busy = true);

    try {
      final transfer =
          await ref.read(inventoryRepositoryProvider).createTransfer(
        toWarehouseId: myWarehouseId,
        transferDate: _date,
        items: [
          for (final line in _lines)
            TransferLineInput(
              productId: line.product.id,
              quantity: line.quantity,
            ),
        ],
      );
      if (!mounted) return;
      showInfoSnack(context, '${transfer.label} requested.');
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
          message: 'Could not create the transfer.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final myWarehouseId = me?.warehouseId;
    final scheme = Theme.of(context).colorScheme;

    if (me == null || myWarehouseId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('New transfer')),
        body: const EmptyView(
          icon: Icons.store_outlined,
          title: 'No store assigned',
          message: 'This account is not tied to a store, so a transfer has no '
              'destination to request stock into.',
        ),
      );
    }

    final totalUnits =
        _lines.fold<double>(0, (sum, line) => sum + line.quantity);

    return Scaffold(
      appBar: AppBar(title: const Text('New transfer')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                SectionCard(
                  title: 'Destination',
                  child: Text(
                    'Requests stock into ${me.storeLabel}. The source store '
                    'is chosen later, when this request is approved.',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SectionCard(
                  title: 'Items',
                  trailing: TextButton.icon(
                    onPressed: _addLine,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add'),
                  ),
                  child: Column(
                    children: [
                      if (_lines.isEmpty)
                        Text(
                          'Add the products you want to bring into this store.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      for (final line in _lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      line.product.name,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      line.product.sku ?? '',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              QuantityStepper(
                                value: line.quantity,
                                min: 0,
                                editable: true,
                                onChanged: (value) => setState(() {
                                  if (value <= 0) {
                                    _lines.remove(line);
                                  } else {
                                    line.quantity = value;
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
                  title: 'When',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.event_outlined),
                    title: const Text('Transfer date'),
                    subtitle: Text(prettyDate(apiDate(_date))),
                    trailing: const Icon(Icons.edit_calendar_outlined),
                    onTap: _pickDate,
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
                onPressed: (_lines.isEmpty || _busy)
                    ? null
                    : () => _submit(myWarehouseId),
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.swap_horiz_rounded),
                label: Text(
                  _busy
                      ? 'Working…'
                      : 'Request transfer (${qty(totalUnits)} unit'
                          '${totalUnits == 1 ? '' : 's'})',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
