import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../data/models/sale.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import '../../widgets/pickers.dart';
import 'sale_return_create_screen.dart';
import 'sale_return_detail_screen.dart';

class SaleReturnsScreen extends ConsumerStatefulWidget {
  const SaleReturnsScreen({super.key, this.showFab = true});

  /// Whether this screen is the tab currently being looked at.
  ///
  /// A Scaffold inside a TabBarView keeps painting its floating action button
  /// even when a sibling tab is on screen, so several "New …" buttons ended up
  /// stacked on each other. Only the active tab shows its own.
  final bool showFab;

  @override
  ConsumerState<SaleReturnsScreen> createState() => _SaleReturnsScreenState();
}

class _SaleReturnsScreenState extends ConsumerState<SaleReturnsScreen> {
  String _search = '';
  int _reload = 0;

  Future<void> _startReturn() async {
    final sale = await pickSale(
      context,
      ref,
      allowedStatuses: SaleStatus.returnable,
      title: 'Which sale is being returned?',
    );
    if (sale == null || !mounted) return;
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SaleReturnCreateScreen(saleId: sale.id),
      ),
    );
    if (created == true && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final sales = ref.read(salesRepositoryProvider);
    final canCreate = me?.can(Perm.saleReturnCreate) ?? false;
    final canView = me?.can(Perm.saleReturnView) ?? false;

    if (!canView) {
      return Scaffold(
        body: EmptyView(
          icon: Icons.assignment_return_outlined,
          title: 'Returns',
          message: canCreate
              ? 'Your role can record returns but not browse them.'
              : "Your role can't work with returns.",
          action: canCreate
              ? FilledButton.icon(
                  onPressed: _startReturn,
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
              heroTag: 'fab-sale-return',
              onPressed: _startReturn,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New return'),
            )
          : null,
      body: PagedListView<SaleReturn>(
        reloadToken: '$_search|$_reload',
        fetch: (page) => sales.listReturns(page: page, search: _search),
        emptyTitle: 'No returns yet',
        emptyMessage: 'Returns recorded against this store show up here.',
        emptyIcon: Icons.assignment_return_outlined,
        header: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: SearchBox(
            hint: 'Return or sale number',
            onChanged: (value) => setState(() => _search = value),
          ),
        ),
        itemBuilder: (context, saleReturn) => _ReturnTile(saleReturn: saleReturn),
      ),
    );
  }
}

class _ReturnTile extends StatelessWidget {
  const _ReturnTile({required this.saleReturn});

  final SaleReturn saleReturn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lineCount = saleReturn.items.length;

    return AppCard(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SaleReturnDetailScreen(returnId: saleReturn.id),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  saleReturn.label,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              Text(
                '− ${money(saleReturn.computedRefund)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: scheme.error,
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
              prettyDate(saleReturn.createdAt),
              if (saleReturn.saleNumber != null)
                'Sale ${saleReturn.saleNumber}'
              else if (saleReturn.saleId != null)
                'Sale #${saleReturn.saleId}',
              if (lineCount > 0) '$lineCount line${lineCount == 1 ? '' : 's'}',
            ].join(' · '),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
          if ((saleReturn.reason ?? '').isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              saleReturn.reason!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
          if (saleReturn.status != null) ...[
            const SizedBox(height: 8),
            StatusChip(status: saleReturn.status, dense: true),
          ],
        ],
      ),
    );
  }
}
