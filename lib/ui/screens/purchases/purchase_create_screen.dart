import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/catalog.dart';
import '../../../state/cart.dart';
import '../../../state/providers.dart';
import '../../widgets/cart_panel.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';

const String _purchaseCart = 'purchase';

/// What the store is doing with this document.
///
/// The API has one create endpoint and it always lands in `DRAFT`; `confirm`
/// moves it to `ORDERED`. That maps exactly onto the two things a store actually
/// wants: raise an indent for someone to approve, or place the order itself. So
/// an indent here is a purchase left in DRAFT, and an order is create-then-
/// confirm in one go. There is no separate indent resource on the server.
enum PurchaseIntent { indent, order }

/// Raise a purchase for this store. The warehouse is implicit — this account
/// can only buy into its own store, so there is no store field.
class PurchaseCreateScreen extends ConsumerStatefulWidget {
  const PurchaseCreateScreen({super.key, this.intent = PurchaseIntent.order});

  /// Which mode the screen opens in. The user can still switch.
  final PurchaseIntent intent;

  @override
  ConsumerState<PurchaseCreateScreen> createState() =>
      _PurchaseCreateScreenState();
}

class _PurchaseCreateScreenState extends ConsumerState<PurchaseCreateScreen> {
  Supplier? _supplier;
  DateTime _purchaseDate = DateTime.now();
  DateTime? _expectedDate;
  final TextEditingController _notes = TextEditingController();
  bool _busy = false;
  String? _supplierError;
  late PurchaseIntent _intent = widget.intent;

  CartController get _cart => ref.read(cartProvider(_purchaseCart).notifier);

  @override
  void initState() {
    super.initState();
    Future.microtask(_cart.clear);
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  Future<void> _addLine() async {
    // Resolved before the await: `ref` is unusable once this screen is gone, and
    // the picker can outlive it (a forced sign-out closes the screen underneath).
    final cart = _cart;
    // A purchase is often exactly how a product gets stock in this warehouse
    // for the first time — it may have no retail price-list entry yet, so
    // the picker must not filter it out the way choosing what to sell would.
    final product = await pickProduct(
      context,
      ref,
      title: 'Add a product',
      includeUnpricedProducts: true,
    );
    if (product != null && mounted) cart.add(product);
  }

  Future<void> _pickDate({required bool expected}) async {
    final now = DateTime.now();
    final initial = expected ? (_expectedDate ?? now) : _purchaseDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (expected) {
        _expectedDate = picked;
      } else {
        _purchaseDate = picked;
      }
    });
  }

  Future<void> _submit(List<CartLine> lines) async {
    final supplier = _supplier;
    if (supplier == null) {
      setState(() => _supplierError = 'Choose a supplier');
      return;
    }
    final warehouseId = ref.read(warehouseIdProvider);
    if (warehouseId == null) {
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'No store is assigned to this account.',
        ),
      );
      return;
    }

    setState(() {
      _supplierError = null;
      _busy = true;
    });

    // Captured before the awaits — reading `ref` after a dispose throws.
    final cart = _cart;
    final repository = ref.read(purchasesRepositoryProvider);
    final wantsOrder = _intent == PurchaseIntent.order &&
        (ref.read(meProvider)?.can(Perm.purchaseUpdate) ?? false);

    try {
      final purchase = await repository.create(
            warehouseId: warehouseId,
            supplierId: supplier.id,
            purchaseDate: _purchaseDate,
            expectedDate: _expectedDate,
            notes: _notes.text,
            items: lines.map((line) => line.toInput()).toList(),
          );

      // Ordering is create-then-confirm. If the confirm fails the purchase still
      // exists as a draft, so say so instead of implying nothing happened —
      // otherwise the user raises it again and ends up with two.
      var message = '${purchase.label} saved as an indent.';
      if (wantsOrder) {
        try {
          await repository.confirm(purchase.id);
          message = '${purchase.label} ordered.';
        } on AppError catch (error) {
          cart.clear();
          if (!mounted) return;
          setState(() => _busy = false);
          showErrorSnack(
            context,
            AppError(
              code: error.code,
              message: '${purchase.label} was saved as an indent but could not '
                  'be ordered: ${error.uiMessage}',
            ),
          );
          Navigator.of(context).pop(true);
          return;
        }
      }

      cart.clear();
      if (!mounted) return;
      showInfoSnack(context, message);
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
          message: 'Could not create the purchase.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = ref.watch(cartProvider(_purchaseCart));
    final allPriced = lines.every((line) => line.isPriced);

    // Confirming is what turns an indent into an order. Without that permission
    // the only honest option is to leave it as an indent for someone who has it.
    final canOrder = ref.watch(meProvider)?.can(Perm.purchaseUpdate) ?? false;
    final intent = canOrder ? _intent : PurchaseIntent.indent;
    final isIndent = intent == PurchaseIntent.indent;

    return Scaffold(
      appBar: AppBar(
        title: Text(isIndent ? 'Purchase indent' : 'New purchase order'),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
              children: [
                SectionCard(
                  title: 'What is this?',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (canOrder)
                        SegmentedButton<PurchaseIntent>(
                          segments: const [
                            ButtonSegment(
                              value: PurchaseIntent.indent,
                              label: Text('Indent'),
                            ),
                            ButtonSegment(
                              value: PurchaseIntent.order,
                              label: Text('Order'),
                            ),
                          ],
                          selected: {intent},
                          showSelectedIcon: false,
                          onSelectionChanged: (selection) => setState(
                            () => _intent = selection.first,
                          ),
                        ),
                      const SizedBox(height: 8),
                      Text(
                        isIndent
                            ? 'A request for stock. Saved as a draft so it can '
                                'be reviewed and ordered later — nothing goes '
                                'to the supplier yet.'
                            : 'Placed with the supplier straight away. Stock '
                                'arrives against it when you receive.',
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
                  title: 'Supplier',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () async {
                          final supplier = await pickSupplier(context, ref);
                          if (supplier != null && mounted) {
                            setState(() {
                              _supplier = supplier;
                              _supplierError = null;
                            });
                          }
                        },
                        icon: const Icon(Icons.factory_outlined),
                        label: Text(_supplier?.name ?? 'Choose a supplier'),
                      ),
                      if (_supplierError != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          _supplierError!,
                          style: TextStyle(color: scheme.error, fontSize: 12),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SectionCard(
                  title: 'Dates',
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('Purchase date'),
                        subtitle: Text(prettyDate(apiDate(_purchaseDate))),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: () => _pickDate(expected: false),
                      ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.schedule_outlined),
                        title: const Text('Expected delivery'),
                        subtitle: Text(
                          _expectedDate == null
                              ? 'Not set'
                              : prettyDate(apiDate(_expectedDate!)),
                        ),
                        trailing: _expectedDate == null
                            ? const Icon(Icons.edit_calendar_outlined)
                            : IconButton(
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () =>
                                    setState(() => _expectedDate = null),
                              ),
                        onTap: () => _pickDate(expected: true),
                      ),
                    ],
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
                      if (lines.isEmpty)
                        Text(
                          isIndent
                              ? 'Add the products being requested, with the '
                                  'expected cost per unit.'
                              : 'Add the products being ordered, with the cost '
                                  'price per unit.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      for (final line in lines)
                        CartLineTile(
                          key: ValueKey('purchase-${line.product.id}'),
                          line: line,
                          onQuantityChanged: (value) =>
                              _cart.setQuantity(line.product.id, value),
                          onPriceChanged: (value) =>
                              _cart.setPrice(line.product.id, value),
                          onRemove: () => _cart.remove(line.product.id),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SectionCard(
                  title: 'Notes',
                  child: TextField(
                    controller: _notes,
                    maxLines: 2,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Optional — reference, instructions',
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
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isIndent ? 'Indent value' : 'Order value',
                        style: TextStyle(
                            fontSize: 12, color: scheme.onSurfaceVariant),
                      ),
                      Text(
                        money(cartSubtotal(lines)),
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: (lines.isEmpty || !allPriced || _busy)
                          ? null
                          : () => _submit(lines),
                      icon: _busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined),
                      label: Text(
                        _busy
                            ? 'Working…'
                            : isIndent
                                ? 'Save indent'
                                : 'Place order',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
