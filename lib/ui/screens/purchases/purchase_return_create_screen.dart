import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/purchase.dart';
import '../../../data/repositories/purchases_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';

/// Send received stock back to a supplier. Scoped against the parent purchase's
/// warehouse server-side, so there is nothing store-related to choose here.
class PurchaseReturnCreateScreen extends ConsumerStatefulWidget {
  const PurchaseReturnCreateScreen({super.key, required this.purchaseId});

  final String purchaseId;

  @override
  ConsumerState<PurchaseReturnCreateScreen> createState() =>
      _PurchaseReturnCreateScreenState();
}

class _PurchaseReturnCreateScreenState
    extends ConsumerState<PurchaseReturnCreateScreen> {
  final Map<String, double> _quantities = {};
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _reasonError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  bool get _hasLines => _quantities.values.any((value) => value > 0);

  Future<void> _submit(Purchase purchase) async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _reasonError = 'A reason is required');
      return;
    }
    setState(() {
      _reasonError = null;
      _busy = true;
    });

    final items = <PurchaseReturnLineInput>[];
    _quantities.forEach((purchaseItemId, quantity) {
      if (quantity > 0) {
        items.add(PurchaseReturnLineInput(
          purchaseItemId: purchaseItemId,
          quantity: quantity,
        ));
      }
    });

    try {
      final result = await ref.read(purchasesRepositoryProvider).createReturn(
            purchaseId: purchase.id,
            reason: reason,
            items: items,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      showInfoSnack(context, '${result.label} recorded.');
      Navigator.of(context).pop(true);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error.isValidation) _reasonError = error.fieldErrors['reason'];
      });
      showErrorSnack(context, error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not record the return.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final purchases = ref.read(purchasesRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Return to supplier')),
      body: AsyncView<Purchase>(
        load: () => purchases.get(widget.purchaseId),
        builder: (context, purchase, reload) => _buildForm(context, purchase),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Purchase purchase) {
    final scheme = Theme.of(context).colorScheme;

    // Only stock that actually arrived can go back.
    final returnable = purchase.items
        .where((item) => (item.receivedQuantity ?? item.quantity) > 0)
        .toList();

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
                    Text(purchase.label,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(
                      '${purchase.supplierName ?? 'Supplier'} · '
                      '${prettyDate(purchase.purchaseDate ?? purchase.createdAt)}',
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
                title: 'What is going back?',
                child: Column(
                  children: [
                    if (returnable.isEmpty)
                      Text(
                        'Nothing on this purchase has been received yet.',
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    for (final item in returnable)
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
                                    'received ${qty(item.receivedQuantity ?? item.quantity)}'
                                    ' × ${money(item.price)}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            QuantityStepper(
                              value: _quantities[item.id] ?? 0,
                              min: 0,
                              max: item.receivedQuantity ?? item.quantity,
                              onChanged: (value) => setState(() {
                                if (value <= 0) {
                                  _quantities.remove(item.id);
                                } else {
                                  _quantities[item.id] = value;
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
                title: 'Reason',
                child: TextField(
                  controller: _reason,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    hintText: 'e.g. damaged in transit, wrong item shipped',
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
              onPressed: (!_hasLines || _busy) ? null : () => _submit(purchase),
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assignment_return_rounded),
              label: Text(_busy ? 'Working…' : 'Record return'),
            ),
          ),
        ),
      ],
    );
  }
}
