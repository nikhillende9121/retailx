import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'state/providers.dart';
import 'ui/screens/root_gate.dart';
import 'ui/theme.dart';

/// Lets code outside the widget tree (the notification tap handler in
/// [RootGate], which fires from a native callback rather than a tap on a
/// widget) push a route without needing a [BuildContext] of its own.
final navigatorKey = GlobalKey<NavigatorState>();

class StoreManagerApp extends ConsumerWidget {
  const StoreManagerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'RetailX',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // Watched, not fixed to `system`: the shop chooses, in Settings.
      themeMode: ref.watch(themeModeProvider),
      home: const RootGate(),
    );
  }
}
