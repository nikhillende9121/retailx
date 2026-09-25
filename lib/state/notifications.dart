import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/notification_repository.dart';

/// Backs the topbar bell's badge. Kept separate from the notification list
/// screen's own state — the badge has to be visible (and refreshable) from the
/// shell regardless of whether that screen has ever been opened.
class UnreadCountController extends StateNotifier<int> {
  UnreadCountController(this._repo) : super(0);

  final NotificationRepository _repo;

  /// Silent on failure — a badge that fails to refresh should stay at its
  /// last known value, not show an error over someone's shoulder.
  Future<void> refresh() async {
    try {
      state = await _repo.unreadCount();
    } catch (_) {
      // Ignored — see above.
    }
  }

  /// Optimistic, so the badge updates the instant a row is tapped rather than
  /// waiting on the mark-as-read round trip.
  void decrement() {
    if (state > 0) state -= 1;
  }

  void clear() => state = 0;
}
