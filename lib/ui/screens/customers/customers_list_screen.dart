import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/formatters.dart';
import '../../../data/models/catalog.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';
import 'customer_detail_screen.dart';

/// Every customer this store has on file, searchable by name/phone/email —
/// the entry point for looking up a customer's credit standing, collecting
/// a payment against what they owe, or reviewing their transaction history.
///
/// Body only, no Scaffold/AppBar of its own — embedded as a tab inside
/// `SalesListScreen`'s TabbedArea, under the shell's shared top bar.
class CustomersListScreen extends ConsumerStatefulWidget {
  const CustomersListScreen({super.key});

  @override
  ConsumerState<CustomersListScreen> createState() =>
      _CustomersListScreenState();
}

class _CustomersListScreenState extends ConsumerState<CustomersListScreen> {
  String _search = '';
  int _reload = 0;

  @override
  Widget build(BuildContext context) {
    final catalog = ref.read(catalogRepositoryProvider);
    final me = ref.watch(meProvider);
    final creditEnabled = me?.hasFeature(Feature.creditPayment) ?? false;

    return PagedListView<Customer>(
      reloadToken: '$_reload$_search',
      fetch: (page) => catalog.customers(page: page, search: _search),
      emptyTitle: 'No customers found',
      emptyIcon: Icons.people_outline_rounded,
      header: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        child: SearchBox(
          hint: 'Name, phone or email',
          onChanged: (value) => setState(() => _search = value),
        ),
      ),
      itemBuilder: (context, customer) => AppCard(
        onTap: () async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => CustomerDetailScreen(customerId: customer.id),
            ),
          );
          if (mounted) setState(() => _reload++);
        },
        child: Row(
          children: [
            CircleAvatar(child: Text(initials(customer.name))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (customer.subtitle.isNotEmpty)
                    Text(
                      customer.subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Only actually calls the credit API when the tenant has the
            // feature at all — otherwise this can only ever come back
            // FEATURE_NOT_ENABLED, so there's no point spending a request
            // per visible row just to learn what's already known.
            creditEnabled
                ? _DueBadge(customerId: customer.id)
                : const _DueBadge.na(),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

/// This customer's current due, fetched once per row — "NA" whenever the
/// backend doesn't send one (credit disabled for the tenant, missing
/// `CREDIT.VIEW`, or any other failure), never a blank space or an error.
class _DueBadge extends ConsumerStatefulWidget {
  const _DueBadge({required this.customerId}) : _skipFetch = false;

  /// Static "NA" with no network call — used when the tenant doesn't have
  /// credit enabled at all, so there's nothing the backend could send.
  const _DueBadge.na()
      : customerId = '',
        _skipFetch = true;

  final String customerId;
  final bool _skipFetch;

  @override
  ConsumerState<_DueBadge> createState() => _DueBadgeState();
}

class _DueBadgeState extends ConsumerState<_DueBadge> {
  double? _due;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    if (widget._skipFetch) {
      _loading = false;
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final summary =
          await ref.read(creditRepositoryProvider).summary(widget.customerId);
      if (!mounted) return;
      setState(() {
        _due = summary.currentBalance;
        _loading = false;
      });
    } catch (_) {
      // Best-effort — see the class doc comment. Missing CREDIT.VIEW, the
      // customer having no credit account yet, or any other failure all
      // land here the same way: show "NA", not an error.
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (_loading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final due = _due;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          'Due',
          style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
        ),
        Text(
          due == null ? 'NA' : money(due),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
            color: due != null && due > 0 ? scheme.error : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
