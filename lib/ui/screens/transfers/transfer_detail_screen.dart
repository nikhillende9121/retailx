import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/inventory.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import 'transfer_approve_screen.dart';
import 'transfer_receive_screen.dart';
import 'transfer_ship_screen.dart';

class TransferDetailScreen extends ConsumerStatefulWidget {
  const TransferDetailScreen({super.key, required this.transferId});

  final String transferId;

  @override
  ConsumerState<TransferDetailScreen> createState() =>
      _TransferDetailScreenState();
}

class _TransferDetailScreenState extends ConsumerState<TransferDetailScreen> {
  int _reload = 0;
  bool _busy = false;

  Future<void> _cancel() async {
    final ok = await confirmAction(
      context,
      title: 'Cancel this transfer?',
      message: 'This cannot be undone.',
      confirmLabel: 'Cancel transfer',
      destructive: true,
    );
    // The dialog can outlive this screen (forced sign-out) — `ref` would throw.
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(inventoryRepositoryProvider).cancelTransfer(widget.transferId);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reload++;
      });
      showInfoSnack(context, 'Transfer cancelled.');
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
          message: 'That action could not be completed.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final inventory = ref.read(inventoryRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Stock transfer')),
      body: AsyncView<StockTransfer>(
        reloadToken: _reload,
        load: () => inventory.transfer(widget.transferId),
        builder: (context, transfer, reload) {
          final status = transfer.status.toUpperCase();
          final myWarehouseId = me?.warehouseId;
          final outgoing = transfer.isOutgoing(myWarehouseId);
          // Both sides are tested positively: an account with no store, or a
          // transfer this store isn't part of, is neither sender nor receiver
          // and gets no lifecycle buttons at all.
          final incoming = myWarehouseId != null &&
              transfer.toWarehouseId == myWarehouseId;

          // Shipping is the sender's job; receiving is the receiver's. Offering
          // the wrong one would be a guaranteed rejection. A transfer only
          // becomes outgoing once a tenant admin approves it (that's what
          // sets fromWarehouseId) — DRAFT has no source yet, so only
          // APPROVED can be shipped.
          // No outgoing/incoming scope check here — fromWarehouseId doesn't
          // exist until this action sets it, so there's nothing yet for this
          // account to be "outgoing" relative to. Only the permission (in
          // practice, held by an unrestricted admin role, not a
          // warehouse-scoped one) and status gate it.
          final canApprove = (me?.can(Perm.transferApprove) ?? false) &&
              status == TransferStatus.draft;
          final canShip = outgoing &&
              (me?.can(Perm.transferShip) ?? false) &&
              status == TransferStatus.approved;
          final canReceive = incoming &&
              (me?.can(Perm.transferReceive) ?? false) &&
              status == TransferStatus.inTransit;
          final canCancel = (outgoing || incoming) &&
              (me?.can(Perm.transferUpdate) ?? false) &&
              (status == TransferStatus.draft ||
                  status == TransferStatus.approved);

          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            transfer.label,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        StatusChip(status: transfer.status),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'From',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                transfer.fromLabel(),
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if ((transfer.fromWarehouseCode ?? '').isNotEmpty)
                                Text(
                                  transfer.fromWarehouseCode!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_rounded,
                            color: scheme.onSurfaceVariant),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                'To',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              Text(
                                transfer.toLabel(),
                                textAlign: TextAlign.right,
                                style:
                                    const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if ((transfer.toWarehouseCode ?? '').isNotEmpty)
                                Text(
                                  transfer.toWarehouseCode!,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    DetailRow(
                      label: 'Date',
                      value:
                          prettyDate(transfer.transferDate ?? transfer.createdAt),
                    ),
                    DetailRow(
                      label: 'Direction',
                      value: outgoing
                          ? 'Leaving this store'
                          : incoming
                              ? 'Coming into this store'
                              : 'Between other stores',
                    ),
                    if ((transfer.notes ?? '').isNotEmpty)
                      DetailRow(label: 'Notes', value: transfer.notes!),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              SectionCard(
                title: 'Items (${transfer.items.length})',
                child: Column(
                  children: [
                    for (final item in transfer.items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                                  if (item.sku != null)
                                    Text(
                                      item.sku!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            // Every stage the line has actually reached —
                            // just "Requested" while still a DRAFT, growing to
                            // Requested/Approved/Shipped/Received as the
                            // transfer moves through its lifecycle.
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                for (final (label, value) in item.quantityStages)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      '$label ${qty(value)}',
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: label == 'Requested'
                                            ? FontWeight.w500
                                            : FontWeight.w700,
                                        color: label == 'Requested'
                                            ? scheme.onSurfaceVariant
                                            : scheme.onSurface,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    const Divider(height: 18),
                    DetailRow(
                      label: 'Total units',
                      value: qty(transfer.totalQuantity),
                      emphasize: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (canApprove)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final approved =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => TransferApproveScreen(
                                  transferId: widget.transferId,
                                ),
                              ),
                            );
                            if (approved == true) reload();
                          },
                    icon: const Icon(Icons.check_circle_outline_rounded),
                    label: const Text('Approve transfer'),
                  ),
                ),
              if (canShip)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final shipped =
                                await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => TransferShipScreen(
                                  transferId: widget.transferId,
                                ),
                              ),
                            );
                            if (shipped == true) reload();
                          },
                    icon: const Icon(Icons.local_shipping_rounded),
                    label: const Text('Mark shipped'),
                  ),
                ),
              if (canReceive)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final received = await Navigator.of(context).push<bool>(
                              MaterialPageRoute(
                                builder: (_) => TransferReceiveScreen(
                                  transferId: widget.transferId,
                                ),
                              ),
                            );
                            if (received == true) reload();
                          },
                    icon: const Icon(Icons.inventory_rounded),
                    label: const Text('Receive into this store'),
                  ),
                ),
              if (canCancel)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _cancel,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Cancel transfer'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: scheme.error,
                      side: BorderSide(color: scheme.error),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
