import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../data/models/sale.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import '../customers/customers_list_screen.dart';
import 'sale_detail_screen.dart';

/// Sales for this store only — the list endpoint is filtered server-side, so
/// there is no store column and no store filter.
class SalesListScreen extends ConsumerStatefulWidget {
  const SalesListScreen({super.key});

  @override
  ConsumerState<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends ConsumerState<SalesListScreen> {
  static const _statusFilters = <String?>[
    null,
    SaleStatus.draft,
    SaleStatus.confirmed,
    SaleStatus.processing,
    SaleStatus.packed,
    SaleStatus.shipped,
    SaleStatus.delivered,
    SaleStatus.completed,
    SaleStatus.cancelled,
  ];

  String _search = '';
  String? _status;
  int _reload = 0;

  /// Summary of the sales currently loaded, recomputed on every page.
  ///
  /// There is no summary endpoint, so these are honest about their scope: they
  /// describe the sales on screen, not the whole ledger. Cancelled sales are
  /// excluded — they took no money.
  List<Sale> _loaded = const [];

  ({double today, int todayCount, double loaded, int loadedCount}) get _summary {
    final now = DateTime.now();
    var today = 0.0;
    var todayCount = 0;
    var total = 0.0;
    var count = 0;

    for (final sale in _loaded) {
      if (sale.status.toUpperCase() == SaleStatus.cancelled) continue;
      total += sale.computedTotal;
      count++;
      final at = sale.sortedAt;
      if (at.year == now.year && at.month == now.month && at.day == now.day) {
        today += sale.computedTotal;
        todayCount++;
      }
    }
    return (today: today, todayCount: todayCount, loaded: total, loadedCount: count);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    // Same gate the Customers entry used to carry on the Profile screen —
    // just applied here now that it's moved into this tab bar instead.
    final showCustomers =
        (me?.hasFeature(Feature.customer) ?? false) &&
            (me?.can(Perm.customerView) ?? false);

    if (!showCustomers) return _salesList(context);

    return TabbedArea(
      tabs: [
        AreaTab(
          label: 'Sales',
          icon: Icons.receipt_long_outlined,
          builder: (_) => _salesList(context),
        ),
        AreaTab(
          label: 'Customers',
          icon: Icons.people_outline_rounded,
          builder: (_) => const CustomersListScreen(),
        ),
      ],
    );
  }

  Widget _salesList(BuildContext context) {
    final sales = ref.read(salesRepositoryProvider);

    return PagedListView<Sale>(
      // `_search` isn't in here: the backend ignores that query param, so
      // there's nothing server-side to reload for it — see `Sale.matches`.
      reloadToken: '$_status|$_reload',
      fetch: (page) => sales.list(page: page, search: _search, status: _status),
      where: (sale) => sale.matches(_search),
      // Newest first, whatever order the server returns them in.
      sort: (a, b) => b.sortedAt.compareTo(a.sortedAt),
      onLoaded: (items) {
        // Rebuild the summary from the accumulated list. Guarded so it doesn't
        // loop: setState here triggers a rebuild, not another fetch.
        if (mounted) setState(() => _loaded = items);
      },
      emptyTitle: 'No sales yet',
      emptyMessage: 'Sales you ring up at the till show up here.',
      emptyIcon: Icons.receipt_long_outlined,
      header: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: SearchBox(
              hint: 'Sale number or customer',
              onChanged: (value) => setState(() => _search = value),
            ),
          ),
          if (_loaded.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: "Today's sales",
                      value: money(_summary.today),
                    ),
                  ),
                  const SizedBox(width: kCardGap),
                  Expanded(
                    child: StatTile(
                      label: 'Orders today',
                      value: '${_summary.todayCount}',
                    ),
                  ),
                ],
              ),
            ),
          if (_loaded.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_summary.loadedCount} sale'
                      '${_summary.loadedCount == 1 ? '' : 's'} loaded · '
                      '${money(_summary.loaded)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
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
                      label: Text(status == null ? 'All' : humanizeCode(status)),
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
      itemBuilder: (context, sale) => SaleListTile(
        sale: sale,
        // Guarded: the detail route outlives this list if the session expires
        // while it's open, and the callback fires on the way back.
        onChanged: () {
          if (mounted) setState(() => _reload++);
        },
      ),
    );
  }
}

class SaleListTile extends StatelessWidget {
  const SaleListTile({super.key, required this.sale, this.onChanged});

  final Sale sale;
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineCount = sale.items.length;

    return AppCard(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => SaleDetailScreen(saleId: sale.id)),
        );
        onChanged?.call();
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.label,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  sale.customerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
                ),
                Text(
                  [
                    prettyDateTime(sale.createdAt ?? sale.saleDate),
                    if (sale.customerContact.isNotEmpty) sale.customerContact,
                    if (lineCount > 0)
                      '$lineCount line${lineCount == 1 ? '' : 's'}',
                  ].join(' · '),
                  maxLines: 2,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money(sale.computedTotal),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
              const SizedBox(height: 5),
              StatusChip(status: sale.status, dense: true),
            ],
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
