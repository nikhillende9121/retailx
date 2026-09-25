import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/purchase.dart';
import '../../../data/repositories/purchases_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import 'purchase_return_create_screen.dart';

class PurchaseDetailScreen extends ConsumerStatefulWidget {
  const PurchaseDetailScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  ConsumerState<PurchaseDetailScreen> createState() =>
      _PurchaseDetailScreenState();
}

class _PurchaseDetailScreenState extends ConsumerState<PurchaseDetailScreen> {
  int _reload = 0;
  bool _busy = false;

  Future<void> _confirm(Purchase purchase) async {
    await _run(() => ref
        .read(purchasesRepositoryProvider)
        .confirm(purchase.id), 'Purchase ordered.');
  }

  Future<void> _cancel(Purchase purchase) async {
    final ok = await confirmAction(
      context,
      title: 'Cancel this purchase?',
      message: 'This cannot be undone.',
      confirmLabel: 'Cancel purchase',
      destructive: true,
    );
    if (!ok) return;
    await _run(
      () => ref.read(purchasesRepositoryProvider).cancel(purchase.id),
      'Purchase cancelled.',
    );
  }

  /// Receiving is where stock actually lands, so partial receipts are
  /// first-class: the sheet pre-fills the outstanding quantity per line and the
  /// cashier can knock it down.
  Future<void> _receive(Purchase purchase) async {
    final pending =
        purchase.items.where((item) => item.pendingQuantity > 0).toList();

    final quantities = <String, double>{
      for (final item in pending) item.id: item.pendingQuantity,
    };

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Receive stock',
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Confirm what actually arrived. Anything left outstanding can '
                  'be received later.',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      if (pending.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Everything on this purchase is received.'),
                        ),
                      for (final item in pending)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.productName),
                                    Text(
                                      'outstanding ${qty(item.pendingQuantity)}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(sheetContext)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              QuantityStepper(
                                value: quantities[item.id] ?? 0,
                                min: 0,
                                max: item.pendingQuantity,
                                onChanged: (value) => setSheetState(
                                  () => quantities[item.id] = value,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: pending.isEmpty
                      ? null
                      : () => Navigator.of(sheetContext).pop(true),
                  icon: const Icon(Icons.inventory_rounded),
                  label: const Text('Receive'),
                ),
                const SizedBox(height: 6),
                TextButton(
                  onPressed: () => Navigator.of(sheetContext).pop(false),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (confirmed != true) return;

    final lines = <ReceiveLineInput>[];
    quantities.forEach((purchaseItemId, quantity) {
      if (quantity > 0) {
        lines.add(ReceiveLineInput(
          purchaseItemId: purchaseItemId,
          quantity: quantity,
        ));
      }
    });
    if (lines.isEmpty) return;

    await _run(
      () => ref.read(purchasesRepositoryProvider).receive(purchase.id, items: lines),
      'Stock received.',
    );
  }

  Future<void> _run(Future<void> Function() task, String successMessage) async {
    // Every caller reaches here after a dialog or sheet, so this screen may
    // already be gone — and `task` closes over `ref`, which would throw too.
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      await task();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reload++;
      });
      showInfoSnack(context, successMessage);
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
          message: 'That action could not be completed.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final purchases = ref.read(purchasesRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Purchase')),
      body: AsyncView<Purchase>(
        reloadToken: _reload,
        load: () => purchases.get(widget.purchaseId),
        builder: (context, purchase, reload) {
          final status = purchase.status.toUpperCase();
          final canUpdate = me?.can(Perm.purchaseUpdate) ?? false;
          final canReceive = me?.can(Perm.purchaseReceive) ?? false;
          final canReturn = (me?.hasFeature(Feature.purchaseReturn) ?? false) &&
              (me?.can(Perm.purchaseReturnCreate) ?? false);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            purchase.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        StatusChip(
                          status: purchase.status,
                          label: status == PurchaseStatus.draft
                              ? 'Indent'
                              : null,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    DetailRow(
                      label: 'Supplier',
                      value: purchase.supplierName ?? '—',
                    ),
                    DetailRow(
                      label: 'Ordered',
                      value: prettyDate(
                        purchase.purchaseDate ?? purchase.createdAt,
                      ),
                    ),
                    if (purchase.expectedDate != null)
                      DetailRow(
                        label: 'Expected',
                        value: prettyDate(purchase.expectedDate),
                      ),
                    if ((purchase.notes ?? '').isNotEmpty)
                      DetailRow(label: 'Notes', value: purchase.notes!),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                title: 'Items (${purchase.items.length})',
                child: Column(
                  children: [
                    for (final item in purchase.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
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
                                    '${qty(item.quantity)} × ${money(item.price)}'
                                    '${item.receivedQuantity != null ? ' · received ${qty(item.receivedQuantity)}' : ''}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: item.pendingQuantity > 0
                                          ? scheme.onSurfaceVariant
                                          : scheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              money(item.amount),
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 18),
                    DetailRow(
                      label: 'Total',
                      value: money(purchase.computedTotal),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (status == PurchaseStatus.draft && canUpdate)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _confirm(purchase),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Approve & order'),
                  ),
                ),
              if ((status == PurchaseStatus.ordered ||
                      status == PurchaseStatus.partiallyReceived) &&
                  canReceive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: _busy ? null : () => _receive(purchase),
                    icon: const Icon(Icons.inventory_rounded),
                    label: const Text('Receive stock'),
                  ),
                ),
              if ((status == PurchaseStatus.draft ||
                      status == PurchaseStatus.ordered) &&
                  canUpdate)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : () => _cancel(purchase),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel purchase'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                    ),
                  ),
                ),
              if (PurchaseStatus.returnable.contains(status) && canReturn)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final created =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => PurchaseReturnCreateScreen(
                                  purchaseId: purchase.id,
                                ),
                              ),
                            );
                            if (created == true && mounted) {
                              setState(() => _reload++);
                            }
                          },
                    icon: const Icon(Icons.assignment_return_outlined),
                    label: const Text('Return to supplier'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
