import 'package:flutter/widgets.dart';

import '../ui/screens/transfers/transfer_detail_screen.dart';

/// Maps a notification's `route`/`entityId` — the same pair carried by a push
/// payload (`NotificationRouter`, `MyFirebaseMessagingService`) and by a row's
/// `data` in the in-app list (`NotificationsScreen`) — to the screen it points
/// at. Shared so a tapped push and a tapped list row can't drift onto
/// different destinations for the same route string.
///
/// Only `STOCK_TRANSFER_DETAIL` is real today — it's the only route the
/// backend ever sends (`stock-transfer.service.ts`). Anything else falls
/// through to null, same as an unrecognized push route.
Widget? screenForNotificationTarget(String? route, String? entityId) {
  if (entityId == null || entityId.isEmpty) return null;
  switch (route) {
    case 'STOCK_TRANSFER_DETAIL':
      return TransferDetailScreen(transferId: entityId);
    default:
      return null;
  }
}
