import '../../core/json.dart';

/// List endpoints wrap data as `{ items: [...], pagination: {...} }`.
class PagedList<T> {
  const PagedList({
    required this.items,
    this.page = 1,
    this.pageSize = 20,
    this.total = 0,
    this.totalPages = 1,
  });

  final List<T> items;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  /// Whether asking for another page is worth doing.
  ///
  /// `items.isNotEmpty` is the load-bearing half: `page` comes from the
  /// response, and a handler that reports `totalPages` but omits `page` pins it
  /// to 1 forever, so `page < totalPages` alone would stay true no matter how
  /// many pages had already been fetched. An empty page is the one signal that
  /// can't lie about having reached the end.
  bool get hasMore => items.isNotEmpty && page < totalPages;

  static PagedList<T> from<T>(
    dynamic data,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    // A bare array (some handlers skip the wrapper for small collections).
    if (data is List) {
      final items = asMapList(data).map(fromJson).toList();
      return PagedList<T>(
        items: items,
        total: items.length,
        totalPages: 1,
      );
    }

    final map = asMap(data);
    // Not `const []`: a constant literal may not reference a type parameter.
    if (map == null) return PagedList<T>(items: <T>[], totalPages: 1);

    final items = asMapList(map['items'] ?? map['data'] ?? map['rows'])
        .map(fromJson)
        .toList();
    final pagination = asMap(map['pagination']) ?? asMap(map['meta']);

    return PagedList<T>(
      items: items,
      page: asInt(pagination?['page'], 1),
      pageSize: asInt(pagination?['pageSize'], items.length),
      total: asInt(pagination?['total'], items.length),
      totalPages: asInt(pagination?['totalPages'], 1),
    );
  }

  PagedList<T> merge(PagedList<T> next) => PagedList<T>(
        items: [...items, ...next.items],
        page: next.page,
        pageSize: next.pageSize,
        total: next.total,
        totalPages: next.totalPages,
      );
}
