import '../../core/constants.dart';
import '../../core/json.dart';
import '../api_client.dart';
import '../models/notification.dart';
import '../models/paged.dart';

class NotificationRepository {
  NotificationRepository(this._api);

  final ApiClient _api;

  Future<PagedList<AppNotification>> list({int page = 1}) async {
    final data = await _api.get('notifications', query: {
      'page': page,
      'pageSize': kPageSize,
    });
    return PagedList.from(data, AppNotification.fromJson);
  }

  Future<int> unreadCount() async {
    final data = await _api.get('notifications/unread-count');
    return asInt(asMap(data)?['unreadCount']);
  }

  Future<void> markAsRead(String id) => _api.patch('notifications/$id/read');

  Future<void> markAllAsRead() => _api.patch('notifications/read-all');
}
