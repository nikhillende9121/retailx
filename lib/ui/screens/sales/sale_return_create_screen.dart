import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// Pick the lines coming back, say why, submit.
///
/// The refund is *never* computed here — the response carries a discount-aware
/// `refundAmount` per line and a `totalRefundAmount`, and that is what the
/// customer is told.
class SaleReturnCreateScreen extends ConsumerStatefulWidget {
  const SaleReturnCreateScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SaleReturnCreateScreen> createState() =>
      _SaleReturnCreateScreenState();
}

class _SaleReturnCreateScreenState
    extends ConsumerState<SaleReturnCreateScreen> {
  final Map<String, double> _quantities = {};
  final TextEditingController _reason = TextEditingController();
  bool _busy = false;
  String? _reasonError;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  double _quantityFor(SaleItem item) => _quantities[item.id] ?? 0;

  bool get _hasLines => _quantities.values.any((value) => value > 0);

  Future<void> _submit(Sale sale) async {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _reasonError = 'A reason is required');
      return;
    }
    setState(() {
      _reasonError = null;
      _busy = true;
    });

    final items = <ReturnLineInput>[];
    _quantities.forEach((saleItemId, quantity) {
      if (quantity > 0) {
        items.add(ReturnLineInput(saleItemId: saleItemId, quantity: quantity));
      }
    });

    try {
      final result = await ref.read(salesRepositoryProvider).createReturn(
            saleId: sale.id,
            reason: reason,
            items: items,
          );
      if (!mounted) return;
      setState(() => _busy = false);
      await _showRefundSheet(result);
      if (mounted) Navigator.of(context).pop(true);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        if (error.isValidation) {
          _reasonError = error.fieldErrors['reason'];
        }
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

  Future<void> _showRefundSheet(SaleReturn result) async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 44, color: successColor(scheme.brightness)),
              const SizedBox(height: 10),
              Text(
                'Return recorded',
                textAlign: TextAlign.center,
                style: Theme.of(sheetContext).textTheme.titleLarge,
              ),
              const SizedBox(height: 14),
              for (final item in result.items)
                DetailRow(
                  label: '${item.productName} × ${qty(item.quantity)}',
                  value: money(item.refundAmount),
                ),
              const Divider(height: 20),
              DetailRow(
                label: 'Refund to customer',
                value: money(result.computedRefund),
                emphasize: true,
                valueColor: successColor(scheme.brightness),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.of(sheetContext).pop(),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sales = ref.read(salesRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('New return')),
      body: AsyncView<Sale>(
        load: () => sales.get(widget.saleId),
        builder: (context, sale, reload) => _buildForm(context, sale),
      ),
    );
  }

  Widget _buildForm(BuildContext context, Sale sale) {
    final scheme = Theme.of(context).colorScheme;
    final returnable =
        sale.items.where((item) => item.availableToReturn > 0).toList();

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
                          Text(
                            sale.label,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
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
                title: 'What is coming back?',
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
                              value: _quantityFor(item),
                              min: 0,
                              max: item.availableToReturn,
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
                    hintText: 'e.g. wrong size, damaged on opening',
                    errorText: _reasonError,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'The refund amount is calculated by the server, taking any '
                'discount on the original sale into account.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: FilledButton.icon(
              onPressed: (!_hasLines || _busy) ? null : () => _submit(sale),
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
