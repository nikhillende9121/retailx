import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../data/models/inventory.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import 'transfer_create_screen.dart';
import 'transfer_detail_screen.dart';
import 'transfer_receive_screen.dart';
import 'transfer_ship_screen.dart';

/// Which slice of the transfer list is on screen.
///
/// The endpoint returns both directions in one list because this store can be on
/// either side. Receiving stock and sending stock are different jobs done by
/// different people at different moments, so the list can be narrowed to one.
enum _Direction { all, incoming, outgoing, toShip, toReceive }

/// Transfers where this store is on either side — stock going out and stock
/// coming in are the same list, distinguished by direction.
class TransfersScreen extends ConsumerStatefulWidget {
  const TransfersScreen({super.key, this.showFab = true});

  /// Whether this screen is the tab currently being looked at.
  ///
  /// A Scaffold inside a TabBarView keeps painting its floating action button
  /// even when a sibling tab is on screen, so several "New …" buttons ended up
  /// stacked on each other. Only the active tab shows its own.
  final bool showFab;

  @override
  ConsumerState<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends ConsumerState<TransfersScreen> {
  String _search = '';
  int _reload = 0;
  _Direction _direction = _Direction.all;
  List<StockTransfer> _loaded = const [];

  bool _incoming(StockTransfer transfer, String? myWarehouseId) =>
      myWarehouseId != null && transfer.toWarehouseId == myWarehouseId;

  /// Shipped or in transit *towards* this store: the goods are on their way and
  /// nobody has booked them in yet.
  bool _awaitingReceipt(StockTransfer transfer, String? myWarehouseId) {
    if (!_incoming(transfer, myWarehouseId)) return false;
    return transfer.status.toUpperCase() == TransferStatus.inTransit;
  }

  /// Approved and leaving *this* store, but nobody has handed the goods to
  /// the courier/booked them out yet — the mirror of [_awaitingReceipt] for
  /// the sending side. A transfer only becomes outgoing once it's approved
  /// (that's what sets `fromWarehouseId`), so status APPROVED already
  /// implies it hasn't shipped yet — no separate DRAFT check needed.
  bool _awaitingShipment(StockTransfer transfer, String? myWarehouseId) {
    if (!transfer.isOutgoing(myWarehouseId)) return false;
    return transfer.status.toUpperCase() == TransferStatus.approved;
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const TransferCreateScreen()),
    );
    if (created == true && mounted) setState(() => _reload++);
  }

  /// Book an inbound transfer in without opening it first.
  ///
  /// Receiving is the one action a store does repeatedly and in bulk — a van
  /// arrives with four transfers on it. Making each one a two-screen trip is
  /// the difference between doing it at the door and doing it later, badly —
  /// but the receive screen itself still lets each line's quantity be
  /// checked/adjusted before it's booked in.
  Future<void> _receive(StockTransfer transfer) async {
    final received = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransferReceiveScreen(transferId: transfer.id),
      ),
    );
    if (received == true && mounted) setState(() => _reload++);
  }

  /// Ship an outbound transfer straight from the list — same convenience as
  /// [_receive], for the store on the other end of the same handoff.
  Future<void> _ship(StockTransfer transfer) async {
    final shipped = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TransferShipScreen(transferId: transfer.id),
      ),
    );
    if (shipped == true && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final inventory = ref.read(inventoryRepositoryProvider);
    final myWarehouseId = me?.warehouseId;
    final canReceive = me?.can(Perm.transferReceive) ?? false;
    final canShip = me?.can(Perm.transferShip) ?? false;
    final scheme = Theme.of(context).colorScheme;

    final inboundWaiting =
        _loaded.where((t) => _awaitingReceipt(t, myWarehouseId)).length;
    final outboundWaiting =
        _loaded.where((t) => _awaitingShipment(t, myWarehouseId)).length;

    return Scaffold(
      floatingActionButton: widget.showFab && (me?.can(Perm.transferCreate) ?? false)
          ? FloatingActionButton.extended(
              // Unique tag: sibling tabs stay mounted in the shell's IndexedStack, so
              // two default-tagged FABs would collide on the next Hero transition.
              heroTag: 'fab-transfer-new',
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New transfer'),
            )
          : null,
      body: PagedListView<StockTransfer>(
        // `_search` isn't in here: the backend ignores that query param, so
        // there's nothing server-side to reload for it — see
        // `StockTransfer.matches`.
        reloadToken: '$_reload',
        fetch: (page) => inventory.transfers(page: page, search: _search),
        where: (transfer) {
          if (!transfer.matches(_search)) return false;
          switch (_direction) {
            case _Direction.all:
              return true;
            case _Direction.incoming:
              return _incoming(transfer, myWarehouseId);
            case _Direction.outgoing:
              return transfer.isOutgoing(myWarehouseId);
            case _Direction.toShip:
              return _awaitingShipment(transfer, myWarehouseId);
            case _Direction.toReceive:
              return _awaitingReceipt(transfer, myWarehouseId);
          }
        },
        onLoaded: (items) {
          if (mounted) setState(() => _loaded = items);
        },
        emptyTitle: switch (_direction) {
          _Direction.toShip => 'Nothing waiting to be shipped',
          _Direction.toReceive => 'Nothing waiting to be received',
          _Direction.incoming => 'No stock coming in',
          _Direction.outgoing => 'No stock going out',
          _Direction.all => 'No transfers yet',
        },
        emptyMessage: 'Stock moving between your store and another one shows '
            'up here, whichever direction it goes.',
        emptyIcon: Icons.swap_horiz_rounded,
        header: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              child: SearchBox(
                hint: 'Transfer number or store',
                onChanged: (value) => setState(() => _search = value),
              ),
            ),
            if (outboundWaiting > 0 && _direction != _Direction.toShip)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Material(
                  // Distinct from the "to receive" banner below it so the
                  // two jobs — send vs. book in — read as different actions
                  // at a glance, the same way the outgoing/incoming icon
                  // tint on each list card does.
                  color: scheme.errorContainer,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    onTap: () => setState(() => _direction = _Direction.toShip),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.local_shipping_rounded,
                              size: 20, color: scheme.onErrorContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$outboundWaiting transfer'
                              '${outboundWaiting == 1 ? '' : 's'} waiting to be '
                              'shipped',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onErrorContainer,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: scheme.onErrorContainer),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            if (inboundWaiting > 0 && _direction != _Direction.toReceive)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Material(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(kRadiusCard),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(kRadiusCard),
                    onTap: () =>
                        setState(() => _direction = _Direction.toReceive),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      child: Row(
                        children: [
                          Icon(Icons.move_to_inbox_rounded,
                              size: 20, color: scheme.onPrimaryContainer),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '$inboundWaiting transfer'
                              '${inboundWaiting == 1 ? '' : 's'} waiting to be '
                              'received',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: scheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: scheme.onPrimaryContainer),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (final entry in const <(_Direction, String)>[
                    (_Direction.all, 'All'),
                    (_Direction.toShip, 'To ship'),
                    (_Direction.toReceive, 'To receive'),
                    (_Direction.incoming, 'Coming in'),
                    (_Direction.outgoing, 'Going out'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(entry.$2),
                        selected: _direction == entry.$1,
                        onSelected: (_) =>
                            setState(() => _direction = entry.$1),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
        itemBuilder: (context, transfer) {
          final outgoing = transfer.isOutgoing(myWarehouseId);
          final receivable = canReceive && _awaitingReceipt(transfer, myWarehouseId);
          final shippable = canShip && _awaitingShipment(transfer, myWarehouseId);

          return AppCard(
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TransferDetailScreen(transferId: transfer.id),
                ),
              );
              if (mounted) setState(() => _reload++);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: outgoing
                            ? scheme.errorContainer
                            : scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        outgoing
                            ? Icons.arrow_upward_rounded
                            : Icons.arrow_downward_rounded,
                        size: 20,
                        color: outgoing
                            ? scheme.onErrorContainer
                            : scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            transfer.label,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 15),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            outgoing
                                ? 'Out to ${transfer.toLabel()}'
                                : 'In from ${transfer.fromLabel()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          Text(
                            '${prettyDate(transfer.transferDate ?? transfer.createdAt)}'
                            ' · ${qty(transfer.totalQuantity)} unit'
                            '${transfer.totalQuantity == 1 ? '' : 's'}',
                            style: TextStyle(
                              fontSize: 12,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    StatusChip(status: transfer.status, dense: true),
                    const Icon(Icons.chevron_right_rounded),
                  ],
                ),
                if (shippable) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _ship(transfer),
                    icon: const Icon(Icons.local_shipping_rounded, size: 18),
                    label: const Text('Ship from this store'),
                  ),
                ],
                if (receivable) ...[
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _receive(transfer),
                    icon: const Icon(Icons.move_to_inbox_rounded, size: 18),
                    label: const Text('Receive into this store'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}
