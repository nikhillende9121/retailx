import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/auth.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/receipt_format.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../printing/default_receipt_schema.dart';
import '../../../printing/receipt_pdf_service.dart';
import '../../../printing/receipt_token_resolver.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/pickers.dart';
import '../../widgets/printer_picker_sheet.dart';

/// One lifecycle transition. Each is its own endpoint — there is no generic
/// "advance the sale" call.
class _Transition {
  const _Transition({
    required this.label,
    required this.action,
    required this.icon,
    required this.permission,
    this.destructive = false,
    this.primary = false,
  });

  final String label;
  final String action;
  final IconData icon;
  final String permission;
  final bool destructive;
  final bool primary;
}

/// Which transitions are legal from a given status. Anything not listed here
/// simply isn't offered, which keeps the user out of guaranteed-403 territory.
List<_Transition> transitionsFor(String status) {
  switch (status.toUpperCase()) {
    case SaleStatus.draft:
      return const [
        _Transition(
          label: 'Confirm',
          action: 'confirm',
          icon: Icons.check_rounded,
          permission: Perm.saleConfirm,
          primary: true,
        ),
        _Transition(
          label: 'Cancel',
          action: 'cancel',
          icon: Icons.close_rounded,
          permission: Perm.saleUpdate,
          destructive: true,
        ),
      ];
    case SaleStatus.confirmed:
      return const [
        _Transition(
          label: 'Complete',
          action: 'complete',
          icon: Icons.task_alt_rounded,
          permission: Perm.saleUpdate,
          primary: true,
        ),
        _Transition(
          label: 'Start processing',
          action: 'process',
          icon: Icons.play_arrow_rounded,
          permission: Perm.saleUpdate,
        ),
        _Transition(
          label: 'Cancel',
          action: 'cancel',
          icon: Icons.close_rounded,
          permission: Perm.saleUpdate,
          destructive: true,
        ),
      ];
    case SaleStatus.processing:
      return const [
        _Transition(
          label: 'Mark packed',
          action: 'pack',
          icon: Icons.inventory_2_outlined,
          permission: Perm.saleUpdate,
          primary: true,
        ),
        _Transition(
          label: 'Cancel',
          action: 'cancel',
          icon: Icons.close_rounded,
          permission: Perm.saleUpdate,
          destructive: true,
        ),
      ];
    case SaleStatus.packed:
      return const [
        _Transition(
          label: 'Mark shipped',
          action: 'ship',
          icon: Icons.local_shipping_outlined,
          permission: Perm.saleShip,
          primary: true,
        ),
      ];
    case SaleStatus.shipped:
      return const [
        _Transition(
          label: 'Mark delivered',
          action: 'deliver',
          icon: Icons.where_to_vote_outlined,
          permission: Perm.saleDeliver,
          primary: true,
        ),
      ];
    case SaleStatus.delivered:
      return const [
        _Transition(
          label: 'Complete',
          action: 'complete',
          icon: Icons.task_alt_rounded,
          permission: Perm.saleUpdate,
          primary: true,
        ),
      ];
    default:
      return const [];
  }
}

class SaleDetailScreen extends ConsumerStatefulWidget {
  const SaleDetailScreen({super.key, required this.saleId});

  final String saleId;

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  int _reload = 0;
  bool _busy = false;

  Future<void> _run(_Transition transition) async {
    if (transition.destructive) {
      final confirmed = await confirmAction(
        context,
        title: '${transition.label} this sale?',
        message: 'This cannot be undone.',
        confirmLabel: transition.label,
        destructive: true,
      );
      if (!confirmed) return;
    }

    // Ship now requires an assignee — picked before anything else runs, so a
    // cashier backing out of the picker leaves the sale untouched rather
    // than mid-transition.
    String? assignedDeliveryUserId;
    if (transition.action == 'ship') {
      final assignee = await pickDeliveryAssignee(context, ref);
      if (assignee == null || !mounted) return;
      assignedDeliveryUserId = assignee.id;
    }

    // The confirm dialog / picker can outlive this screen if the session
    // expires while it's up; `ref` and `setState` are both dead by then.
    if (!mounted) return;
    setState(() => _busy = true);
    try {
      final sales = ref.read(salesRepositoryProvider);
      if (transition.action == 'ship') {
        await sales.ship(
          widget.saleId,
          assignedDeliveryUserId: assignedDeliveryUserId!,
        );
      } else {
        await sales.action(widget.saleId, transition.action);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _reload++;
      });
      showInfoSnack(context, '${transition.label} done.');
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

  /// Reprints a past sale — the items here are already resolved to real
  /// names by [build]'s `load()`, so this only needs the shop/tenant header.
  Future<void> _printReceipt(Sale sale) async {
    final me = ref.read(meProvider);
    final warehouseId = me?.warehouseId ?? sale.warehouseId;
    if (warehouseId == null) return;

    try {
      final catalog = ref.read(catalogRepositoryProvider);

      var resolvedSale = sale;
      if (resolvedSale.needsCustomerLookup ||
          (resolvedSale.customerId != null && resolvedSale.customerPhone == null)) {
        try {
          final cust = await catalog.customer(resolvedSale.customerId!);
          if (cust != null) {
            resolvedSale = resolvedSale.withCustomer(cust);
          }
        } catch (_) {}
      }

      Warehouse shop;
      try {
        shop = await catalog.warehouse(warehouseId) ??
            Warehouse(
              id: warehouseId,
              name: resolvedSale.warehouseName ?? me?.warehouseName ?? me?.storeLabel ?? 'Store',
              address: me?.warehouseAddress,
            );
      } on AppError {
        shop = Warehouse(
          id: warehouseId,
          name: resolvedSale.warehouseName ?? me?.warehouseName ?? me?.storeLabel ?? 'Store',
          address: me?.warehouseAddress,
        );
      }

      if (shop.address == null || shop.address!.trim().isEmpty) {
        if (me?.warehouseAddress != null && me!.warehouseAddress!.trim().isNotEmpty) {
          shop = Warehouse(
            id: shop.id,
            name: shop.name,
            code: shop.code,
            address: me.warehouseAddress,
          );
        } else {
          try {
            final warehouses = await catalog.warehouses();
            for (final w in warehouses) {
              if (w.id == warehouseId && w.address != null && w.address!.trim().isNotEmpty) {
                shop = w;
                break;
              }
            }
          } catch (_) {}
        }
      }

      final tenant = await catalog.tenantProfile();

      // Fetch the server's receipt format, falling back to the bundled default.
      ReceiptFormat? format;
      try {
        final formatRepo = ref.read(receiptFormatRepositoryProvider);
        final posId = ref.read(tokenStoreProvider).deviceId ?? warehouseId;
        format = await formatRepo.fetchIfStale(posId);
      } catch (_) {}
      format ??= kDefaultReceiptFormat;

      // Desktop/web: use PDF → native print dialog.
      if (ReceiptPdfService.shouldUsePdfPrinting) {
        final tokens = ReceiptTokenResolver.buildTokens(
          sale: resolvedSale,
          shop: shop,
          tenant: tenant,
          cashierName: me?.name,
        );
        await ReceiptPdfService.printReceipt(
          format: format,
          tokens: tokens,
          items: resolvedSale.items,
          jobName: resolvedSale.label,
        );
        if (!mounted) return;
        showInfoSnack(context, 'Receipt sent to printer.');
        return;
      }

      // Android: Bluetooth ESC/POS thermal printer.
      final tokenStore = ref.read(tokenStoreProvider);
      final printerService = ref.read(printerServiceProvider);
      if (tokenStore.printerAddress == null) {
        final internal = await printerService.autoDetectInternalPrinter();
        if (internal != null) {
          try {
            await printerService.connect(internal.macAdress);
            await tokenStore.setPrinter(internal.macAdress, internal.name);
          } catch (_) {}
        }
        if (tokenStore.printerAddress == null) {
          final picked = await showPrinterPicker(context);
          if (picked != true || !mounted) return;
        }
      }

      final printer = ref.read(printerServiceProvider);
      if (!await printer.isConnected) {
        final address = tokenStore.printerAddress;
        if (address == null) return;
        await printer.connect(address);
      }

      await printer.printWithFormat(
        sale: resolvedSale,
        shop: shop,
        tenant: tenant,
        format: format,
        cashierName: me?.name,
      );
      if (!mounted) return;
      showInfoSnack(context, 'Receipt printed.');
    } on AppError catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    } catch (_) {
      if (!mounted) return;
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not print the receipt.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final sales = ref.read(salesRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Sale')),
      body: AsyncView<Sale>(
        reloadToken: _reload,
        // If the server returns customerId without expanding the relation, fetch
        // the customer so this screen can show a name and phone rather than an id.
        load: () async {
          var sale = await sales.get(widget.saleId);
          final catalog = ref.read(catalogRepositoryProvider);

          if (sale.needsCustomerLookup) {
            try {
              final customer = await catalog.customer(sale.customerId!);
              if (customer != null) sale = sale.withCustomer(customer);
            } on AppError {
              // No permission to read customers, or it's gone — the id still shows.
            }
          }

          if (sale.needsWarehouseLookup) {
            try {
              final warehouse = await catalog.warehouse(sale.warehouseId!);
              if (warehouse != null) sale = sale.withWarehouseName(warehouse.name);
            } on AppError {
              // No permission to read warehouses — the id still shows.
            }
          }

          if (sale.needsItemProductLookup) {
            final names = await resolveProductNames(
              catalog,
              sale.items
                  .where((item) => item.needsProductLookup)
                  .map((item) => item.productId),
            );
            if (names.isNotEmpty) {
              sale = sale.withItems([
                for (final item in sale.items)
                  if (names[item.productId] case final name?)
                    item.withProductName(name)
                  else
                    item,
              ]);
            }
          }

          return sale;
        },
        builder: (context, sale, reload) => _SaleBody(
          sale: sale,
          me: me,
          busy: _busy,
          onRun: _run,
          onPrint: _printReceipt,
        ),
      ),
    );
  }
}

class _SaleBody extends StatelessWidget {
  const _SaleBody({
    required this.sale,
    required this.me,
    required this.busy,
    required this.onRun,
    required this.onPrint,
  });

  final Sale sale;
  final Me? me;
  final bool busy;
  final Future<void> Function(_Transition) onRun;
  final Future<void> Function(Sale) onPrint;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final available = transitionsFor(sale.status).where((transition) {
      if (!(me?.can(transition.permission) ?? false)) return false;
      // A sale with an assignee can only be delivered by that person or a
      // SALE.UPDATE holder (manager override) — mirrors the server-side
      // check so this button doesn't sit there just to 403 when tapped. A
      // sale shipped before this feature existed (or by an older app build)
      // has no assignee at all, so any SALE.DELIVER holder still qualifies —
      // same backward-compat rule the server applies.
      if (transition.action == 'deliver') {
        final assignedTo = sale.assignedDeliveryUserId;
        if (assignedTo != null &&
            assignedTo != me?.id &&
            !(me?.can(Perm.saleUpdate) ?? false)) {
          return false;
        }
      }
      return true;
    }).toList();

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
                      sale.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  StatusChip(status: sale.status),
                ],
              ),
              const SizedBox(height: 10),
              DetailRow(
                label: 'Date',
                value: prettyDateTime(sale.createdAt ?? sale.saleDate),
              ),
              DetailRow(label: 'Customer', value: sale.customerLabel),
              if (sale.customerPhone != null)
                DetailRow(label: 'Phone', value: sale.customerPhone!),
              if (sale.customerEmail != null)
                DetailRow(label: 'Email', value: sale.customerEmail!),
              DetailRow(label: 'Channel', value: humanizeCode(sale.channel)),
              DetailRow(
                label: 'Store',
                value: sale.warehouseName ??
                    (sale.warehouseId != null
                        ? 'Store #${sale.warehouseId}'
                        : '—'),
              ),
              if (sale.assignedDeliveryUserId != null)
                DetailRow(
                  label: 'Assigned to',
                  value: sale.assignedDeliveryUserName ??
                      'User #${sale.assignedDeliveryUserId}',
                ),
              if (sale.updatedAt != null)
                DetailRow(
                  label: 'Last updated',
                  value: prettyDateTime(sale.updatedAt),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Items (${sale.items.length})',
          child: Column(
            children: [
              if (sale.items.isEmpty)
                Text(
                  'This sale has no line items.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              for (final item in sale.items) ...[
                if (item != sale.items.first)
                  Divider(height: 1, color: scheme.outlineVariant),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${qty(item.quantity)} × ${money(item.price)}'
                              '${item.sku != null ? ' · ${item.sku}' : ''}',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            if (item.taxes.isNotEmpty)
                              Text(
                                item.taxes
                                    .map((t) =>
                                        '${t.component} ${qty(t.ratePercent)}% ${money(t.amount)}')
                                    .join(' · '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            money(item.amount),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          if (item.tax > 0)
                            Text(
                              '+ ${money(item.tax)} tax',
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        if (sale.discounts.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            title: 'Discounts (${sale.discounts.length})',
            child: Column(
              children: [
                for (final discount in sale.discounts)
                  DetailRow(
                    label: discount.isCoupon
                        ? 'Coupon #${discount.couponId}'
                        : discount.isLineLevel
                            ? 'Line discount #${discount.discountId ?? discount.id}'
                            : 'Order discount #${discount.discountId ?? discount.id}',
                    value: '− ${money(discount.amount)}',
                    valueColor: successColor(scheme.brightness),
                  ),
              ],
            ),
          ),
        ],
        if (sale.charges.isNotEmpty) ...[
          const SizedBox(height: 10),
          SectionCard(
            title: 'Charges (${sale.charges.length})',
            child: Column(
              children: [
                for (final charge in sale.charges)
                  DetailRow(
                    label: charge.name,
                    value: charge.taxAmount > 0
                        ? '${money(charge.amount)} + ${money(charge.taxAmount)} tax'
                        : money(charge.amount),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        SectionCard(
          title: 'Totals',
          child: Column(
            children: [
              DetailRow(label: 'Subtotal', value: money(sale.itemsSubtotal)),
              if (sale.discountTotal > 0)
                DetailRow(
                  label: 'Discount',
                  value: '− ${money(sale.discountTotal)}',
                  valueColor: successColor(scheme.brightness),
                ),
              if (sale.chargesTotal > 0)
                DetailRow(label: 'Charges', value: money(sale.chargesTotal)),
              if (sale.itemsTaxTotal + sale.chargesTaxTotal > 0)
                DetailRow(
                  label: 'Tax (incl.)',
                  value: money(sale.itemsTaxTotal + sale.chargesTaxTotal),
                ),
              const Divider(height: 18),
              DetailRow(
                label: 'Total',
                value: money(sale.computedTotal),
                emphasize: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        FilledButton.tonalIcon(
          onPressed: () => onPrint(sale),
          icon: const Icon(Icons.print_outlined),
          label: const Text('Print receipt'),
        ),
        if (available.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            'Actions',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final transition in available)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: transition.primary
                  ? FilledButton.icon(
                      onPressed: busy ? null : () => onRun(transition),
                      icon: Icon(transition.icon),
                      label: Text(transition.label),
                    )
                  : OutlinedButton.icon(
                      onPressed: busy ? null : () => onRun(transition),
                      icon: Icon(transition.icon),
                      label: Text(transition.label),
                      style: transition.destructive
                          ? OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(color: scheme.error),
                            )
                          : null,
                    ),
            ),
        ],
      ],
    );
  }
}
