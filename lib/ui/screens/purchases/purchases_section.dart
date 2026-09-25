import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import 'purchase_returns_screen.dart';
import 'purchases_list_screen.dart';

/// Inbound goods: purchases and returns to suppliers.
class PurchasesSection extends ConsumerWidget {
  const PurchasesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    if (me == null) return const LoadingView();

    final tabs = <AreaTab>[];

    if (me.hasFeature(Feature.purchase) && me.can(Perm.purchaseView)) {
      tabs.add(AreaTab(
        label: 'Purchases',
        builder: (active) => PurchasesListScreen(showFab: active),
      ));
    }
    if (me.hasFeature(Feature.purchaseReturn) &&
        me.canAny([Perm.purchaseReturnView, Perm.purchaseReturnCreate])) {
      tabs.add(AreaTab(
        label: 'Supplier returns',
        builder: (active) => PurchaseReturnsScreen(showFab: active),
      ));
    }

    if (tabs.isEmpty) return const NoAccessView(what: 'Purchases');
    return TabbedArea(tabs: tabs);
  }
}
