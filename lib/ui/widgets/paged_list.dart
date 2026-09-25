import 'package:flutter/material.dart';

import '../../core/errors.dart';
import '../../data/models/paged.dart';
import 'common.dart';

typedef PageFetcher<T> = Future<PagedList<T>> Function(int page);

/// Infinite-scrolling, pull-to-refresh list over a paginated endpoint.
///
/// Every list in the app goes through this so pagination, retry, empty state and
/// refresh behave identically everywhere.
class PagedListView<T> extends StatefulWidget {
  const PagedListView({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.reloadToken,
    this.emptyTitle = 'Nothing here yet',
    this.emptyMessage,
    this.emptyIcon = Icons.inbox_outlined,
    this.emptyAction,
    this.padding = const EdgeInsets.fromLTRB(12, 12, 12, 96),
    this.itemSpacing = 8,
    this.header,
    this.onLoaded,
    this.sort,
    this.where,
  });

  final PageFetcher<T> fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;

  /// Change this (e.g. to the current search text or a refresh counter) to
  /// force a reload from page 1.
  final Object? reloadToken;

  final String emptyTitle;
  final String? emptyMessage;
  final IconData emptyIcon;
  final Widget? emptyAction;
  final EdgeInsetsGeometry padding;
  final double itemSpacing;
  final Widget? header;
  final void Function(List<T> items)? onLoaded;

  /// Applied to the whole accumulated list after every load.
  ///
  /// Sorting per page would be wrong once a second page arrives, so the
  /// comparator runs over everything loaded so far. Server-side ordering is
  /// still requested where the endpoint supports it; this guarantees the order
  /// regardless of what comes back.
  final int Function(T a, T b)? sort;

  /// Client-side filter over the accumulated list.
  ///
  /// For distinctions the endpoint can't express — "transfers coming *into* this
  /// store" is one field comparison the server doesn't take as a query param.
  /// Changing the predicate doesn't refetch; it just narrows what's shown, and
  /// paging keeps going while the narrowed list is too short to scroll.
  final bool Function(T item)? where;

  @override
  State<PagedListView<T>> createState() => _PagedListViewState<T>();
}

class _PagedListViewState<T> extends State<PagedListView<T>> {
  final ScrollController _scroll = ScrollController();
  final List<T> _items = [];

  AppError? _error;
  bool _loading = true;
  bool _loadingMore = false;
  int _page = 1;
  bool _hasMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(reset: true);
  }

  @override
  void didUpdateWidget(PagedListView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadToken != widget.reloadToken) {
      _load(reset: true);
      return;
    }
    // A newly-narrowed filter can empty the viewport without any fetch
    // happening, which would otherwise strand the list on "nothing here".
    _fillViewport();
  }

  /// What the list actually shows: everything loaded, minus the filter.
  List<T> get _visible {
    final test = widget.where;
    if (test == null) return _items;
    return _items.where(test).toList(growable: false);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _applySort() {
    final comparator = widget.sort;
    if (comparator != null) _items.sort(comparator);
  }

  /// Backstop against a server that never says "no more".
  ///
  /// Auto-paging is driven by "the viewport isn't full", which a client-side
  /// filter can keep true indefinitely. If pagination metadata is also wrong,
  /// nothing else stops the loop — 50 pages is far past any real store's list
  /// and cheap insurance against hammering the API.
  static const int _maxPages = 50;

  /// Keeps paging while the list is too short to scroll.
  ///
  /// Without this, a caller that filters a page down to nothing (the sale
  /// picker's "returnable only", the stock screen's "in stock only") would show
  /// an empty state forever: there is nothing to scroll, so no scroll
  /// notification ever asks for page 2.
  void _fillViewport() {
    if (!_hasMore) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_hasMore || _loading || _loadingMore) return;
      final noRoomToScroll =
          !_scroll.hasClients || _scroll.position.maxScrollExtent <= 0;
      if (noRoomToScroll) _loadMore();
    });
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    // Prefetch just before the end so the Load More button is rarely the thing
    // the user has to reach for — it's a fallback, not the only way forward.
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadMore();
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
      });
    }
    try {
      final result = await widget.fetch(1);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(result.items);
        _applySort();
        _page = result.page;
        _hasMore = result.hasMore;
        _loading = false;
        _error = null;
      });
      widget.onLoaded?.call(List<T>.unmodifiable(_items));
      _fillViewport();
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = const AppError(
          code: ErrorCodes.unknown,
          message: 'Something went wrong.',
        );
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _loading || !_hasMore) return;
    if (_page >= _maxPages) {
      setState(() => _hasMore = false);
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final result = await widget.fetch(_page + 1);
      if (!mounted) return;
      setState(() {
        _items.addAll(result.items);
        _applySort();
        _page = result.page > _page ? result.page : _page + 1;
        // An empty page ends it regardless of what the metadata claims.
        _hasMore = result.items.isNotEmpty && result.hasMore;
        _loadingMore = false;
      });
      widget.onLoaded?.call(List<T>.unmodifiable(_items));
      _fillViewport();
    } catch (_) {
      if (!mounted) return;
      // A failed "next page" shouldn't wipe what's already on screen.
      setState(() {
        _loadingMore = false;
        _hasMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final header = widget.header;
    final visible = _visible;

    if (_loading && visible.isEmpty) {
      return Column(
        children: [
          if (header != null) header,
          const Expanded(child: LoadingView()),
        ],
      );
    }

    final error = _error;
    if (error != null && visible.isEmpty) {
      return Column(
        children: [
          if (header != null) header,
          Expanded(
            child: ErrorView(error: error, onRetry: () => _load(reset: true)),
          ),
        ],
      );
    }

    if (visible.isEmpty) {
      return Column(
        children: [
          if (header != null) header,
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView(
                // Same controller as the populated list, so an empty first page
                // can still trigger _loadMore.
                controller: _scroll,
                children: [
                  SizedBox(
                    height: 380,
                    child: EmptyView(
                      title: widget.emptyTitle,
                      message: widget.emptyMessage,
                      icon: widget.emptyIcon,
                      action: widget.emptyAction,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        if (header != null) header,
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => _load(reset: true),
            child: ListView.separated(
              controller: _scroll,
              padding: widget.padding,
              itemCount: visible.length + (_hasMore ? 1 : 0),
              separatorBuilder: (_, __) => SizedBox(height: widget.itemSpacing),
              itemBuilder: (context, index) {
                if (index >= visible.length) {
                  // Explicit paging control, per the design's "Load More".
                  // Auto-paging still happens when the viewport isn't full.
                  return LoadMoreButton(
                    busy: _loadingMore,
                    onPressed: _loadMore,
                  );
                }
                return widget.itemBuilder(context, visible[index]);
              },
            ),
          ),
        ),
      ],
    );
  }
}
