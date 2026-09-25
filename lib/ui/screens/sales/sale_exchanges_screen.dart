import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../data/models/sale.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/pickers.dart';
import '../../theme.dart';
import 'sale_exchange_create_screen.dart';
import 'sale_exchange_detail_screen.dart';

class SaleExchangesScreen extends ConsumerStatefulWidget {
  const SaleExchangesScreen({super.key, this.showFab = true});

  /// Whether this screen is the tab currently being looked at.
  ///
  /// A Scaffold inside a TabBarView keeps painting its floating action button
  /// even when a sibling tab is on screen, so several "New …" buttons ended up
  /// stacked on each other. Only the active tab shows its own.
  final bool showFab;

  @override
  ConsumerState<SaleExchangesScreen> createState() =>
      _SaleExchangesScreenState();
}

class _SaleExchangesScreenState extends ConsumerState<SaleExchangesScreen> {
  String _search = '';
  int _reload = 0;

  Future<void> _startExchange() async {
    final sale = await pickSale(
      context,
      ref,
      allowedStatuses: SaleStatus.returnable,
      title: 'Which sale is being exchanged?',
    );
    if (sale == null || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SaleExchangeCreateScreen(saleId: sale.id),
      ),
    );
    if (created == true && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final sales = ref.read(salesRepositoryProvider);

    return Scaffold(
      floatingActionButton: !widget.showFab
          ? null
          : FloatingActionButton.extended(
              // Unique tag: sibling tabs stay mounted in the shell's IndexedStack,
              // so two default-tagged FABs would collide on the next Hero
              // transition.
              heroTag: 'fab-exchange-new',
              onPressed: _startExchange,
              // Matches every other "New …" FAB in the app (return, purchase,
              // transfer, stock adjust) rather than standing out with a
              // swap-specific glyph.
              icon: const Icon(Icons.add_rounded),
              label: const Text('New exchange'),
            ),
      body: PagedListView<SaleExchange>(
        reloadToken: '$_search|$_reload',
        fetch: (page) => sales.listExchanges(page: page, search: _search),
        emptyTitle: 'No exchanges yet',
        emptyMessage: 'An exchange takes items back and sends the customer out '
            'with replacements in one transaction.',
        emptyIcon: Icons.swap_horiz_rounded,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SearchBox(
            hint: 'Exchange or sale number',
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        itemBuilder: (context, exchange) => _ExchangeTile(exchange: exchange),
      ),
    );
  }
}

/// Copy + colour for the settlement line. This is the number the cashier acts
/// on, so it gets the loudest treatment on the tile.
({String label, Color color, IconData icon}) differenceStyle(
  BuildContext context,
  SaleExchange exchange,
) {
  final scheme = Theme.of(context).colorScheme;
  final amount = (exchange.differenceAmount ?? 0).abs();
  switch (exchange.direction) {
    case DifferenceDirection.customerOwes:
      // Neutral emphasis: something is still owed, but owing isn't a decline
      // or an error — it doesn't borrow the reserved error red.
      return (
        label: 'Customer owes ${money(amount)}',
        color: scheme.onSurface,
        icon: Icons.arrow_downward_rounded,
      );
    case DifferenceDirection.refundDue:
      return (
        label: 'Refund ${money(amount)}',
        color: successColor(scheme.brightness),
        icon: Icons.arrow_upward_rounded,
      );
    case DifferenceDirection.even:
      return (
        label: 'Even swap',
        color: scheme.onSurfaceVariant,
        icon: Icons.horizontal_rule_rounded,
      );
  }
}

class _ExchangeTile extends StatelessWidget {
  const _ExchangeTile({required this.exchange});

  final SaleExchange exchange;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = differenceStyle(context, exchange);

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SaleExchangeDetailScreen(exchangeId: exchange.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exchange.label,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Icon(style.icon, size: 16, color: style.color),
              const SizedBox(width: 4),
              Text(
                style.label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: style.color,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded,
                  color: scheme.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            [
              prettyDate(exchange.createdAt),
              if (exchange.saleId != null) 'Sale #${exchange.saleId}',
              '${exchange.returnItems.length} back',
              '${exchange.newItems.length} out',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if ((exchange.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              exchange.reason!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}
