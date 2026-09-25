import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../data/models/purchase.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/pickers.dart';
import 'purchase_return_create_screen.dart';

class PurchaseReturnsScreen extends ConsumerStatefulWidget {
  const PurchaseReturnsScreen({super.key, this.showFab = true});

  /// Whether this screen is the tab currently being looked at.
  ///
  /// A Scaffold inside a TabBarView keeps painting its floating action button
  /// even when a sibling tab is on screen, so several "New …" buttons ended up
  /// stacked on each other. Only the active tab shows its own.
  final bool showFab;

  @override
  ConsumerState<PurchaseReturnsScreen> createState() =>
      _PurchaseReturnsScreenState();
}

class _PurchaseReturnsScreenState extends ConsumerState<PurchaseReturnsScreen> {
  String _search = '';
  int _reload = 0;

  Future<void> _start() async {
    final purchase = await pickPurchase(
      context,
      ref,
      allowedStatuses: PurchaseStatus.returnable,
    );
    if (purchase == null || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => PurchaseReturnCreateScreen(purchaseId: purchase.id),
      ),
    );
    if (created == true && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final purchases = ref.read(purchasesRepositoryProvider);
    final canCreate = me?.can(Perm.purchaseReturnCreate) ?? false;

    if (!(me?.can(Perm.purchaseReturnView) ?? false)) {
      return Scaffold(
        body: EmptyView(
          icon: Icons.assignment_return_outlined,
          title: 'Supplier returns',
          message: canCreate
              ? 'Your role can record supplier returns but not browse them.'
              : "Your role can't work with supplier returns.",
          action: canCreate
              ? FilledButton.icon(
                  onPressed: _start,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('New return'),
                )
              : null,
        ),
      );
    }

    return Scaffold(
      floatingActionButton: widget.showFab && canCreate
          ? FloatingActionButton.extended(
              // Unique tag: sibling tabs stay mounted in the shell's IndexedStack, so
              // two default-tagged FABs would collide on the next Hero transition.
              heroTag: 'fab-purchase-return',
              onPressed: _start,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New return'),
            )
          : null,
      body: PagedListView<PurchaseReturn>(
        reloadToken: '$_search|$_reload',
        fetch: (page) => purchases.listReturns(page: page, search: _search),
        emptyTitle: 'No supplier returns yet',
        emptyMessage: 'Stock sent back to a supplier shows up here.',
        emptyIcon: Icons.assignment_return_outlined,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SearchBox(
            hint: 'Return or purchase number',
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        itemBuilder: (context, purchaseReturn) => AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      purchaseReturn.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                  if (purchaseReturn.totalAmount != null)
                    Text(
                      money(purchaseReturn.totalAmount),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                [
                  prettyDate(purchaseReturn.createdAt),
                  if (purchaseReturn.purchaseNumber != null)
                    'Purchase ${purchaseReturn.purchaseNumber}'
                  else if (purchaseReturn.purchaseId != null)
                    'Purchase #${purchaseReturn.purchaseId}',
                  '${purchaseReturn.items.length} line'
                      '${purchaseReturn.items.length == 1 ? '' : 's'}',
                ].join(' · '),
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              if ((purchaseReturn.reason ?? '').isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  purchaseReturn.reason!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (purchaseReturn.status != null) ...[
                const SizedBox(height: 8),
                StatusChip(status: purchaseReturn.status, dense: true),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
