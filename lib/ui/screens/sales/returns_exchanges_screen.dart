import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import 'sale_exchanges_screen.dart';
import 'sale_returns_screen.dart';

/// Returns and exchanges behind one nav entry.
///
/// They're the same counter conversation — a customer brought something back —
/// and the only difference is whether they leave with a refund or with different
/// stock. Two separate destinations made the cashier decide before they'd
/// finished talking to the customer; tabs let them switch after.
class ReturnsExchangesScreen extends ConsumerWidget {
  const ReturnsExchangesScreen({super.key, this.showFab = true});

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

    if (me.hasFeature(Feature.saleReturn) &&
        me.canAny([Perm.saleReturnView, Perm.saleReturnCreate])) {
      tabs.add(AreaTab(
        label: 'Returns',
        icon: Icons.assignment_return_outlined,
        builder: (active) => SaleReturnsScreen(showFab: active),
      ));
    }
    if (me.hasFeature(Feature.saleExchange) && me.can(Perm.saleExchange)) {
      tabs.add(AreaTab(
        label: 'Exchanges',
        icon: Icons.swap_horiz_rounded,
        builder: (active) => SaleExchangesScreen(showFab: active),
      ));
    }

    if (tabs.isEmpty) return const NoAccessView(what: 'Returns and exchanges');
    return TabbedArea(tabs: tabs, visible: showFab);
  }
}
