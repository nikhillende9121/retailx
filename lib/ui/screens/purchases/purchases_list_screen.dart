import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../data/models/purchase.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import 'purchase_create_screen.dart';
import 'purchase_detail_screen.dart';

class PurchasesListScreen extends ConsumerStatefulWidget {
  const PurchasesListScreen({super.key, this.showFab = true});

  /// Whether this screen is the tab currently being looked at.
  ///
  /// A Scaffold inside a TabBarView keeps painting its floating action button
  /// even when a sibling tab is on screen, so several "New …" buttons ended up
  /// stacked on each other. Only the active tab shows its own.
  final bool showFab;

  @override
  ConsumerState<PurchasesListScreen> createState() =>
      _PurchasesListScreenState();
}

class _PurchasesListScreenState extends ConsumerState<PurchasesListScreen> {
  static const _statusFilters = <String?>[
    null,
    PurchaseStatus.draft,
    PurchaseStatus.ordered,
    PurchaseStatus.partiallyReceived,
    PurchaseStatus.received,
    PurchaseStatus.cancelled,
  ];

  String _search = '';
  String? _status;
  int _reload = 0;

  /// A DRAFT purchase *is* the indent — the server has no separate resource, and
  /// `confirm` is what turns it into an order. So the list calls DRAFT "Indent"
  /// rather than exposing the storage word.
  static String _statusLabel(String? status) {
    if (status == null) return 'All';
    if (status == PurchaseStatus.draft) return 'Indents';
    return humanizeCode(status);
  }

  Future<void> _create({PurchaseIntent? intent}) async {
    // Standing on the Indents filter and tapping New should give an indent —
    // the filter is the user already saying which of the two they mean.
    final mode = intent ??
        (_status == PurchaseStatus.draft
            ? PurchaseIntent.indent
            : PurchaseIntent.order);
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => PurchaseCreateScreen(intent: mode)),
    );
    if (created == true && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final purchases = ref.read(purchasesRepositoryProvider);

    return Scaffold(
      floatingActionButton: widget.showFab && (me?.can(Perm.purchaseCreate) ?? false)
          ? FloatingActionButton.extended(
              // Unique tag: sibling tabs stay mounted in the shell's IndexedStack, so
              // two default-tagged FABs would collide on the next Hero transition.
              heroTag: 'fab-purchase-new',
              onPressed: () => _create(),
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _status == PurchaseStatus.draft ? 'New indent' : 'New purchase',
              ),
            )
          : null,
      body: PagedListView<Purchase>(
        reloadToken: '$_search|$_status|$_reload',
        fetch: (page) =>
            purchases.list(page: page, search: _search, status: _status),
        emptyTitle: _status == PurchaseStatus.draft
            ? 'No open indents'
            : 'No purchases yet',
        emptyMessage: _status == PurchaseStatus.draft
            ? 'An indent is a request for stock, saved as a draft until it is '
                'approved and ordered.'
            : 'Raise a purchase to bring stock into this store.',
        emptyIcon: Icons.local_shipping_outlined,
        header: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: SearchBox(
                hint: 'Purchase number or supplier',
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final status in _statusFilters)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(_statusLabel(status)),
                        selected: _status == status,
                        onSelected: (_) => setState(() => _status = status),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
        itemBuilder: (context, purchase) => AppCard(
          onTap: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PurchaseDetailScreen(purchaseId: purchase.id),
              ),
            );
            if (mounted) setState(() => _reload++);
          },
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      purchase.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        prettyDate(purchase.purchaseDate ?? purchase.createdAt),
                        purchase.supplierName ?? 'Supplier',
                        if (purchase.items.isNotEmpty)
                          '${purchase.items.length} line'
                              '${purchase.items.length == 1 ? '' : 's'}',
                      ].join(' · '),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money(purchase.computedTotal),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  const SizedBox(height: 5),
                  StatusChip(
                    status: purchase.status,
                    dense: true,
                    label: purchase.status.toUpperCase() ==
                            PurchaseStatus.draft
                        ? 'Indent'
                        : null,
                  ),
                ],
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}
