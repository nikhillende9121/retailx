import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../purchases/purchase_returns_screen.dart';
import '../purchases/purchases_list_screen.dart';
import '../transfers/transfers_screen.dart';
import 'inventory_screen.dart';

/// On-hand stock, stock movements, and how stock arrives, behind one nav
/// entry.
///
/// All three answer the same question — "what have I got, and what's coming
/// or going?" — a transfer or a purchase is only interesting relative to the
/// balance it changes. Keeping them adjacent means checking stock and
/// chasing an inbound purchase or transfer is one destination, not several.
class StockScreen extends ConsumerWidget {
  const StockScreen({super.key, this.showFab = true});

  /// Whether this screen is the bottom-nav tab currently being looked at.
  ///
  /// The shell keeps visited tabs mounted in an [IndexedStack], and a Scaffold
  /// inside it keeps painting its floating action button even when a sibling
  /// tab is on screen — which is why "New return", "New exchange" and
  /// "New transfer" appeared stacked on each other.
  final bool showFab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) return const LoadingView();

    final tabs = <AreaTab>[];

    if (me.hasFeature(Feature.inventory) && me.can(Perm.inventoryView)) {
      tabs.add(AreaTab(
        label: 'On hand',
        icon: Icons.inventory_2_outlined,
        builder: (active) => InventoryScreen(showFab: active),
      ));
    }
    if (me.hasFeature(Feature.stockTransfer) && me.can(Perm.transferView)) {
      tabs.add(AreaTab(
        label: 'Transfers',
        icon: Icons.swap_vert_rounded,
        builder: (active) => TransfersScreen(showFab: active),
      ));
    }
    if (me.hasFeature(Feature.purchase) && me.can(Perm.purchaseView)) {
      tabs.add(AreaTab(
        label: 'Purchases',
        icon: Icons.local_shipping_outlined,
        builder: (active) => PurchasesListScreen(showFab: active),
      ));
    }
    // Moved here from the removed drawer sidebar — same reasoning as
    // Transfers/Purchases above: it's a purchase-side stock movement, not a
    // separate destination.
    if (me.hasFeature(Feature.purchaseReturn) &&
        me.canAny([Perm.purchaseReturnView, Perm.purchaseReturnCreate])) {
      tabs.add(AreaTab(
        label: 'Supplier returns',
        icon: Icons.assignment_returned_outlined,
        builder: (active) => PurchaseReturnsScreen(showFab: active),
      ));
    }

    if (tabs.isEmpty) return const NoAccessView(what: 'Stock');
    return TabbedArea(tabs: tabs, visible: showFab);
  }
}
