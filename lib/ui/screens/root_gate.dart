import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app.dart';
import '../../data/models/catalog.dart';
import '../../services/notification_router.dart';
import '../../services/notification_targets.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../widgets/app_icon_glyph.dart';
import 'login_screen.dart';
import 'shell_screen.dart';

/// Decides what the app shows based on session state: splash while restoring,
/// login when there's no session, a store choice for an unscoped account, and
/// the store shell once everything is known.
class RootGate extends ConsumerStatefulWidget {
  const RootGate({super.key});

  @override
  ConsumerState<RootGate> createState() => _RootGateState();
}

class _RootGateState extends ConsumerState<RootGate> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(sessionProvider.notifier).bootstrap();
      // bootstrap() is what loads the keystore, so the saved theme is only
      // readable afterwards. Guarded: bootstrap outlives a fast sign-out.
      if (mounted) ref.read(themeModeProvider.notifier).syncFromStore();
      _wireNotificationRouting();
    });
  }

  /// A tap can arrive two ways: live, while the app is already running
  /// ([NotificationRouter.onTap]), or as the reason a cold start happened —
  /// in which case native cached it, and [consumeInitialRoute] is the only
  /// chance to pick it up.
  void _wireNotificationRouting() {
    NotificationRouter.onTap = _navigateForNotification;
    NotificationRouter.startListening();
    NotificationRouter.consumeInitialRoute().then((data) {
      if (data != null) _navigateForNotification(data);
    });
  }

  /// Route -> screen mapping lives in [screenForNotificationTarget], shared
  /// with a tap on a row in the in-app notification list, so the two can't
  /// drift onto different destinations for the same route string.
  void _navigateForNotification(Map<String, String> data) {
    // A tap that arrives before/without a session (e.g. after signing out) has
    // nowhere safe to deep-link to — the login screen is already what's shown.
    if (ref.read(sessionProvider) is! SessionReady) return;
    final screen = screenForNotificationTarget(data['route'], data['entityId']);
    if (screen == null) return;
    navigatorKey.currentState?.push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sessionProvider);

    return switch (state) {
      SessionLoading() => const _SplashScreen(),
      SessionLoggedOut(notice: final notice) => LoginScreen(notice: notice),
      SessionNeedsStore(options: final options) => _StorePickerScreen(options: options),
      SessionReady() => const ShellScreen(),
    };
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIconGlyph(height: 56, color: scheme.primary),
            const SizedBox(height: 20),
            Text('RetailX', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 24),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Only reachable for a login that isn't restricted to one warehouse (a tenant
/// admin). A real Store Manager account never sees this — its store comes from
/// `/auth/me`.
class _StorePickerScreen extends ConsumerWidget {
  const _StorePickerScreen({required this.options});

  final List<Warehouse> options;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose your store'),
        actions: [
          IconButton(
            tooltip: 'Sign out',
            onPressed: () => ref.read(sessionProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'This account can operate more than one store. Pick the one you are '
            'working from — every sale, receipt and transfer will be recorded '
            'against it.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          for (final warehouse in options)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.store_mall_directory_outlined),
                title: Text(warehouse.name),
                subtitle:
                    warehouse.subtitle.isEmpty ? null : Text(warehouse.subtitle),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () =>
                    ref.read(sessionProvider.notifier).selectStore(warehouse),
              ),
            ),
        ],
      ),
    );
  }
}
