import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import 'checkout_screen.dart';
import 'sale_exchanges_screen.dart';
import 'sale_returns_screen.dart';
import 'sales_list_screen.dart';

/// Sales area: till, history, returns, exchanges. Sub-tabs are built from the
/// same permission + feature rules as the bottom nav, so a role that can sell
/// but not refund simply has fewer tabs.
class SalesSection extends ConsumerWidget {
  const SalesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) return const LoadingView();

    final tabs = <AreaTab>[];

    if (me.hasFeature(Feature.sales) && me.can(Perm.saleCreate)) {
      tabs.add(AreaTab(
        label: 'Till',
        icon: Icons.point_of_sale_rounded,
        builder: (_) => const CheckoutScreen(),
      ));
    }
    if (me.hasFeature(Feature.sales) && me.can(Perm.saleView)) {
      tabs.add(const AreaTab(
        label: 'Sales',
        icon: Icons.receipt_long_outlined,
        builder: _salesList,
      ));
    }
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

    if (tabs.isEmpty) return const NoAccessView(what: 'Sales');
    return TabbedArea(tabs: tabs);
  }
}

/// Top-level so the tab can be `const` — history has no floating button.
Widget _salesList(bool active) => const SalesListScreen();
