import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/formatters.dart';
import '../../data/demo_backend.dart';
import '../../data/models/auth.dart';
import '../../state/providers.dart';
import '../widgets/app_icon_glyph.dart';
import '../widgets/common.dart';
import 'inventory/stock_screen.dart';
import 'more/more_screen.dart';
import 'notifications/notifications_screen.dart';
import 'sales/checkout_screen.dart';
import 'sales/returns_exchanges_screen.dart';
import 'sales/sales_list_screen.dart';

/// Cycles through System → Light → Dark → System.
void cycleTheme(WidgetRef ref) {
  final current = ref.read(themeModeProvider);
  final next = switch (current) {
    ThemeMode.system => ThemeMode.light,
    ThemeMode.light => ThemeMode.dark,
    ThemeMode.dark => ThemeMode.system,
  };
  ref.read(themeModeProvider.notifier).set(next);
}

IconData _themeModeIcon(ThemeMode mode) => switch (mode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };

String _themeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'System theme',
      ThemeMode.light => 'Light theme',
      ThemeMode.dark => 'Dark theme',
    };

/// The persistent top bar: store icon, store name, live clock.
///
/// The store name is on screen at all times deliberately — every document this
/// app creates belongs to one warehouse, and mis-reading which store you're on
/// is the expensive mistake.
class StoreTopBar extends ConsumerWidget implements PreferredSizeWidget {
  const StoreTopBar({
    super.key,
    this.now,
    this.leading,
    this.actions = const [],
    this.title,
    this.showThemeToggle = false,
    this.showNotificationBell = false,
  });

  final DateTime? now;
  final Widget? leading;
  final List<Widget> actions;

  /// Overrides the store name — used on pushed routes like "Purchases".
  final String? title;

  /// Show the theme-cycle button directly in the app bar (for pushed routes
  /// that don't have a drawer).
  final bool showThemeToggle;

  /// Show the notifications bell — only the main shell's bar does; it's the
  /// one place a badge needs to be visible at all times regardless of which
  /// tab is open.
  final bool showNotificationBell;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(meProvider);
    final scheme = Theme.of(context).colorScheme;
    final time = now ?? DateTime.now();
    final themeMode = ref.watch(themeModeProvider);

    return AppBar(
      backgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      // A pushed route always supplies its own (a back arrow); the main
      // shell never does, so it gets the app's own logo instead of the
      // removed drawer's hamburger — nothing to tap, just the brand mark.
      leading: leading ??
          Center(child: AppIconGlyph(height: 22, color: scheme.onSurface)),
      automaticallyImplyLeading: false,
      titleSpacing: 0,
      title: Text(
        title ?? (me?.storeLabel ?? 'Store'),
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.titleLarge,
      ),
      actions: [
        if (DemoBackend.enabled)
          Container(
            margin: const EdgeInsets.only(right: 2),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: scheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'DEMO',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
                color: scheme.onTertiaryContainer,
              ),
            ),
          ),
        ...actions,
        if (showNotificationBell) const _NotificationBell(),
        if (showThemeToggle)
          IconButton(
            tooltip: _themeLabel(themeMode),
            icon: Icon(_themeModeIcon(themeMode)),
            onPressed: () => cycleTheme(ref),
          ),
        Padding(
          padding: const EdgeInsets.only(right: 14, left: 4),
          child: Center(
            child: Text(
              clock(time),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Bell icon with an unread-count badge. Pushing [NotificationsScreen] and
/// refreshing on return (rather than trying to keep the badge live via some
/// polling stream) is enough — a stale badge for the few seconds someone is
/// already looking at the list is not worth the complexity of anything fancier.
class _NotificationBell extends ConsumerWidget {
  const _NotificationBell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider);
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const NotificationsScreen()),
        );
        if (context.mounted) {
          ref.read(unreadCountProvider.notifier).refresh();
        }
      },
      icon: Badge(
        label: Text(count > 9 ? '9+' : '$count'),
        isLabelVisible: count > 0,
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

class _Tab {
  const _Tab({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.buildChild,
    this.isTill = false,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget Function(bool visible) buildChild;

  /// True for whichever tab is "Sales" — the app's default landing tab,
  /// regardless of where it sits visually in the bar.
  final bool isTill;
}

/// Bottom tabs for the shop floor — sell, review history, take back, check
/// stock, and profile.
///
/// The split follows how often each is touched during a shift, not the shape of
/// the API: returns and exchanges are one destination, and so are stock and
/// transfers. Sales sits in the middle of the bar — the thumb's natural resting
/// spot — even though it's still where the app opens by default. Profile is
/// always last, so it lands on the right of the bar.
class ShellScreen extends ConsumerStatefulWidget {
  const ShellScreen({super.key});

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen> {
  /// Null until the first build, when it's set to wherever the Sales tab
  /// landed — Sales is no longer always index 0, now that it sits in the
  /// middle of the bar, but the app should still open on it.
  int? _index;

  /// Tabs the user has actually opened.
  ///
  /// IndexedStack builds every child, so without this the till, Returns and
  /// Inventory all fire their first request on launch — three round trips for
  /// screens nobody has looked at yet. Visited tabs stay mounted afterwards, so
  /// a half-built cart still survives switching away and back.
  final Set<int> _visited = {};

  late Timer _clockTimer;
  late Timer _unreadTimer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    // Nothing pushes the badge live — the app has no socket/SSE channel — so
    // it's polled: once on open, then on a slow interval. No push notification
    // arriving is exactly the case this covers (a transfer marked read on
    // another device, say), not just a backstop for a missed one.
    ref.read(unreadCountProvider.notifier).refresh();
    _unreadTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      ref.read(unreadCountProvider.notifier).refresh();
    });
    // A till showing the wrong time is worse than showing none.
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    _unreadTimer.cancel();
    super.dispose();
  }

  /// Destinations, with Sales in the middle of the bar and Profile always
  /// last, so it lands on the right.
  ///
  /// Returns and exchanges share one destination, and so do stock and
  /// transfers — each pair is one job, not two. Sales isn't first in this
  /// list because it isn't first in the bar — see [_Tab.isTill] for how the
  /// app still opens on it regardless of where it sits visually.
  List<_Tab> _tabs(Me me) {
    final tabs = <_Tab>[];

    final canReturn = me.hasFeature(Feature.saleReturn) &&
        me.canAny([Perm.saleReturnView, Perm.saleReturnCreate]);
    final canExchange =
        me.hasFeature(Feature.saleExchange) && me.can(Perm.saleExchange);
    if (canReturn || canExchange) {
      tabs.add(_Tab(
        label: 'Returns',
        icon: Icons.assignment_return_outlined,
        selectedIcon: Icons.assignment_return_rounded,
        buildChild: (visible) => ReturnsExchangesScreen(showFab: visible),
      ));
    }

    final canStock =
        me.hasFeature(Feature.inventory) && me.can(Perm.inventoryView);
    final canTransfer =
        me.hasFeature(Feature.stockTransfer) && me.can(Perm.transferView);
    final canPurchase =
        me.hasFeature(Feature.purchase) && me.can(Perm.purchaseView);
    if (canStock || canTransfer || canPurchase) {
      tabs.add(_Tab(
        label: 'Stock',
        icon: Icons.inventory_2_outlined,
        selectedIcon: Icons.inventory_2_rounded,
        buildChild: (visible) => StockScreen(showFab: visible),
      ));
    }

    if (me.hasFeature(Feature.sales) && me.can(Perm.saleCreate)) {
      tabs.add(_Tab(
        label: 'Sales',
        icon: Icons.point_of_sale_outlined,
        selectedIcon: Icons.point_of_sale_rounded,
        isTill: true,
        buildChild: (_) => const CheckoutScreen(),
      ));
      // Only when Sales is the till — when it isn't, the till-less "Sales" tab
      // below is already the history, so a second tab would be a second door
      // to the same room.
      if (me.can(Perm.saleView)) {
        tabs.add(_Tab(
          label: 'History',
          icon: Icons.history_outlined,
          selectedIcon: Icons.history_rounded,
          buildChild: (_) => const SalesListScreen(),
        ));
      }
    } else if (me.hasFeature(Feature.sales) && me.can(Perm.saleView)) {
      // Can read sales but not ring them up — the history is the useful landing.
      tabs.add(_Tab(
        label: 'Sales',
        icon: Icons.receipt_long_outlined,
        selectedIcon: Icons.receipt_long_rounded,
        isTill: true,
        buildChild: (_) => const SalesListScreen(),
      ));
    }

    // Profile always lands last, so it sits on the right of the bar —
    // the corner people expect account/store info to live in.
    tabs.add(_Tab(
      label: 'Profile',
      icon: Icons.person_outline_rounded,
      selectedIcon: Icons.person_rounded,
      buildChild: (_) => const MoreScreen(),
    ));

    return tabs;
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    if (me == null) return const Scaffold(body: LoadingView());

    final tabs = _tabs(me);
    final scheme = Theme.of(context).colorScheme;

    if (tabs.isEmpty) {
      return Scaffold(
        appBar: StoreTopBar(now: _now),
        body: const NoAccessView(what: 'The store floor'),
      );
    }

    if (_index == null) {
      final till = tabs.indexWhere((tab) => tab.isTill);
      _index = till >= 0 ? till : 0;
      _visited.add(_index!);
    }
    final index = _index!.clamp(0, tabs.length - 1);

    final body = IndexedStack(
      index: index,
      children: [
        for (var i = 0; i < tabs.length; i++)
          if (_visited.contains(i))
            tabs[i].buildChild(i == index)
          else
            const SizedBox.shrink(),
      ],
    );

    void onSelect(int value) => setState(() {
          _index = value;
          _visited.add(value);
        });

    // Anything wider than a phone gets a side rail instead of a bottom bar —
    // a thumb reaching across a tablet or desktop screen to tap the bottom
    // edge is the phone ergonomics this bar was designed around, not
    // theirs. 600 is Material's own phone/tablet cutoff.
    final isLargeDisplay = MediaQuery.sizeOf(context).width >= 600;

    return Scaffold(
      // The keyboard covers the tab body instead of shrinking it.
      //
      // Every tab is a fixed header over a scrollable list or grid, and the only
      // field in that header is the search box at the very top — which the
      // keyboard never covers. Letting the viewport shrink instead squeezed the
      // till's Expanded grid to zero on a 360×740 phone and overflowed the
      // column. Text entry that needs to stay visible (dialogs, sheets, the
      // pushed create screens) lives in its own route and handles its own insets.
      resizeToAvoidBottomInset: false,
      appBar: StoreTopBar(
        now: _now,
        showNotificationBell: true,
      ),
      body: (tabs.length < 2 || !isLargeDisplay)
          ? body
          : Row(
              children: [
                Container(
                  width: 88,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLowest,
                    border:
                        Border(right: BorderSide(color: scheme.outlineVariant)),
                  ),
                  // No pill/indicator — same signal as the bottom bar: the
                  // active destination is the brand blue, filled icon, a
                  // touch larger than its idle siblings. Each destination
                  // gets its own vertical padding so the rail doesn't read
                  // as one packed column.
                  child: NavigationRail(
                    backgroundColor: Colors.transparent,
                    selectedIndex: index,
                    onDestinationSelected: onSelect,
                    labelType: NavigationRailLabelType.all,
                    useIndicator: false,
                    minWidth: 88,
                    leading: const SizedBox(height: 16),
                    selectedLabelTextStyle: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    unselectedLabelTextStyle: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                    destinations: [
                      for (final tab in tabs)
                        NavigationRailDestination(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          icon: Icon(tab.selectedIcon,
                              size: 24, color: scheme.onSurfaceVariant),
                          selectedIcon: Icon(tab.selectedIcon,
                              size: 28, color: scheme.primary),
                          label: Text(tab.label),
                        ),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
      bottomNavigationBar: (tabs.length < 2 || isLargeDisplay)
          ? null
          : Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: scheme.outlineVariant)),
              ),
              child: NavigationBar(
                selectedIndex: index,
                onDestinationSelected: onSelect,
                destinations: [
                  for (final tab in tabs)
                    NavigationDestination(
                      // Both states use the filled/rounded glyph, not the thin
                      // outlined one `tab.icon` still carries — Flutter's
                      // classic Icons font has no adjustable stroke weight, so
                      // "bolder" means the filled variant everywhere, not a
                      // thicker outline. Selected stays the brand blue and a
                      // touch larger, the whole signal since there's no
                      // indicator pill — the side rail mirrors this exactly.
                      icon: Icon(tab.selectedIcon,
                          size: 26, color: scheme.onSurfaceVariant),
                      selectedIcon: Icon(tab.selectedIcon,
                          size: 34, color: scheme.primary),
                      label: tab.label,
                    ),
                ],
              ),
            ),
    );
  }
}

