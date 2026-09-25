import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/inventory.dart';
import '../../../data/models/paged.dart';
import '../../../state/providers.dart';
import '../../widgets/cart_panel.dart' show ProductThumb;
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/pickers.dart';

/// On-hand stock for this store, plus manual corrections.
///
/// There is no list endpoint for past adjustments, so this screen deliberately
/// doesn't pretend to show an adjustment history.
class InventoryScreen extends ConsumerStatefulWidget {
  const InventoryScreen({super.key, this.showFab = true});

  /// Whether this screen is the tab currently being looked at.
  ///
  /// A Scaffold inside a TabBarView keeps painting its floating action button
  /// even when a sibling tab is on screen, so several "New …" buttons ended up
  /// stacked on each other. Only the active tab shows its own.
  final bool showFab;

  @override
  ConsumerState<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends ConsumerState<InventoryScreen> {
  String _search = '';
  int _reload = 0;
  bool _onlyInStock = false;

  Future<void> _adjust({StockBalance? preset}) async {
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

    var target = preset;
    if (target == null) {
      target = await pickStockBalance(context, ref, title: 'Adjust which product?');
      if (target == null || !mounted) return;
    }

    final result = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (sheetContext) => _AdjustSheet(
        balance: target!,
        warehouseId: warehouseId,
      ),
    );

    if (result == true && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final inventory = ref.read(inventoryRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;
    final canAdjust = me?.can(Perm.inventoryAdjust) ?? false;

    return Scaffold(
      floatingActionButton: widget.showFab && canAdjust
          ? FloatingActionButton.extended(
              // Unique tag: sibling tabs stay mounted in the shell's IndexedStack, so
              // two default-tagged FABs would collide on the next Hero transition.
              heroTag: 'fab-stock-adjust',
              onPressed: _adjust,
              icon: const Icon(Icons.tune_rounded),
              label: const Text('Adjust stock'),
            )
          : null,
      body: PagedListView<StockBalance>(
        reloadToken: '$_search|$_reload|$_onlyInStock',
        fetch: (page) async {
          final result = await inventory.balance(
            page: page,
            search: _search,
            warehouseId: ref.read(warehouseIdProvider),
          );
          if (!_onlyInStock) return result;
          // The endpoint has no "in stock" flag, so filter the page locally.
          return PagedList<StockBalance>(
            items: result.items.where((balance) => balance.inStock).toList(),
            page: result.page,
            pageSize: result.pageSize,
            total: result.total,
            totalPages: result.totalPages,
          );
        },
        emptyTitle: 'No stock recorded',
        emptyMessage: 'Receive a purchase or a transfer to put stock on the '
            'shelves of this store.',
        emptyIcon: Icons.inventory_2_outlined,
        header: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: SearchBox(
                hint: 'Product name or SKU',
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  FilterChip(
                    label: const Text('In stock only'),
                    selected: _onlyInStock,
                    onSelected: (value) => setState(() => _onlyInStock = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
        itemBuilder: (context, balance) {
          return AppCard(
            onTap: canAdjust ? () => _adjust(preset: balance) : null,
            child: Row(
              children: [
                ProductThumb(
                  name: balance.productName,
                  imageUrl: balance.imageUrl,
                  size: 48,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        balance.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (balance.sku != null || balance.unit != null)
                        Text(
                          [balance.sku, balance.unit]
                              .whereType<String>()
                              .join(' · '),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      if (balance.defaultPrice != null)
                        Text(
                          money(balance.defaultPrice),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: scheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      qty(balance.quantity),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: balance.inStock ? null : scheme.error,
                      ),
                    ),
                    Text(
                      balance.reservedQuantity != null &&
                              balance.reservedQuantity! > 0
                          ? '${qty(balance.reservedQuantity)} reserved'
                          : 'on hand',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Increase or decrease on-hand stock with a reason.
class _AdjustSheet extends ConsumerStatefulWidget {
  const _AdjustSheet({required this.balance, required this.warehouseId});

  final StockBalance balance;
  final String warehouseId;

  @override
  ConsumerState<_AdjustSheet> createState() => _AdjustSheetState();
}

class _AdjustSheetState extends ConsumerState<_AdjustSheet> {
  final TextEditingController _quantity = TextEditingController(text: '1');
  final TextEditingController _reason = TextEditingController();
  bool _increase = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  double get _amount => double.tryParse(_quantity.text.trim()) ?? 0;

  Future<void> _submit() async {
    final reason = _reason.text.trim();
    if (_amount <= 0) {
      setState(() => _error = 'Enter a quantity greater than zero');
      return;
    }
    if (reason.isEmpty) {
      setState(() => _error = 'A reason is required');
      return;
    }
    if (!_increase && _amount > widget.balance.quantity) {
      setState(() => _error =
          'Only ${qty(widget.balance.quantity)} on hand — cannot write off more.');
      return;
    }

    setState(() {
      _error = null;
      _busy = true;
    });

    try {
      await ref.read(inventoryRepositoryProvider).adjust(
            warehouseId: widget.warehouseId,
            productId: widget.balance.productId,
            quantity: _increase ? _amount : -_amount,
            reason: reason,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.uiMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save the adjustment.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final projected = widget.balance.quantity + (_increase ? _amount : -_amount);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Adjust stock',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 2),
              Text(
                '${widget.balance.productName} · ${qty(widget.balance.quantity)} on hand',
                style: TextStyle(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.add_rounded),
                    label: Text('Add'),
                  ),
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.remove_rounded),
                    label: Text('Write off'),
                  ),
                ],
                selected: {_increase},
                onSelectionChanged: (values) =>
                    setState(() => _increase = values.first),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _quantity,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(labelText: 'Quantity'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reason,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Reason',
                  hintText: 'e.g. stock count correction, damaged goods',
                ),
              ),
              const SizedBox(height: 12),
              DetailRow(
                label: 'On hand after this',
                value: qty(projected),
                emphasize: true,
                valueColor: projected < 0 ? scheme.error : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _submit,
                icon: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(_busy ? 'Working…' : 'Save adjustment'),
              ),
              const SizedBox(height: 6),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
