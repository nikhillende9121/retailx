import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../data/models/notification.dart';
import '../../../data/models/paged.dart';
import '../../../services/notification_targets.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import '../shell_screen.dart' show StoreTopBar;

/// Shows every notification the backend has recorded for this user — read and
/// unread together, unread ones marked with a dot and a coloured edge (until
/// this visit auto-marks them read — see [initState]) — with tapping either
/// just navigating or, when it carries a `route`/`entityId` (the same pair a
/// push payload carries), opening the screen it points at.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  /// Marked-read locally so the dot disappears immediately rather than
  /// waiting on a round trip.
  final Map<String, bool> _readOverrides = {};
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    // Opening this screen IS the "I've seen these" signal — nothing left for
    // the user to tap. Deferred to after this frame: this push is itself
    // triggered from inside another widget's build (the shell's bell icon),
    // so mutating unreadCountProvider synchronously here throws "setState()
    // or markNeedsBuild() called during build". Fire-and-forget otherwise —
    // the badge already clears locally, so a failure here just means the
    // server's copy falls out of sync until the next mark-as-read call
    // catches it up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(unreadCountProvider.notifier).clear();
      ref.read(notificationRepositoryProvider).markAllAsRead().catchError((_) {});
    });
  }

  Future<PagedList<AppNotification>> _fetch(int page) {
    return ref.read(notificationRepositoryProvider).list(page: page);
  }

  Future<void> _onTapItem(AppNotification item, bool isRead) async {
    if (!isRead) {
      setState(() => _readOverrides[item.id] = true);
      ref.read(unreadCountProvider.notifier).decrement();
      // Fire-and-forget: the row already looks read: a failure here just means
      // the server's copy falls out of sync until the next full reload.
      ref.read(notificationRepositoryProvider).markAsRead(item.id).catchError((_) {});
    }
    final screen = screenForNotificationTarget(item.route, item.entityId);
    if (screen != null && mounted) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: StoreTopBar(
        title: 'Notifications',
        showThemeToggle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: PagedListView<AppNotification>(
        fetch: _fetch,
        reloadToken: _reloadToken,
        emptyTitle: 'No notifications yet',
        emptyMessage: "You'll see stock transfer and store updates here.",
        emptyIcon: Icons.notifications_none_rounded,
        itemBuilder: (context, item) => _NotificationTile(
          item: item,
          isRead: _readOverrides[item.id] ?? item.isRead,
          onTap: (isRead) => _onTapItem(item, isRead),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.item,
    required this.isRead,
    required this.onTap,
  });

  final AppNotification item;
  final bool isRead;
  final void Function(bool isRead) onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return AppCard(
      statusEdge: isRead ? null : scheme.primary,
      onTap: () => onTap(isRead),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: isRead ? FontWeight.w500 : FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  item.message,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 6),
                Text(
                  timeAgo(item.createdAt),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (!isRead)
            Padding(
              padding: const EdgeInsets.only(left: 10, top: 4),
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
