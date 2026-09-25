import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../data/models/credit.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import '../../widgets/paged_list.dart';

/// A customer's full credit ledger, newest first — a statement of account:
/// what moved it (label), how much and which way (signed amount), and the
/// running balance right afterward, so it reads top-to-bottom like a real
/// statement. See `credit_androidChanges.md` §5.
class CreditTransactionsScreen extends ConsumerWidget {
  const CreditTransactionsScreen({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  final String customerId;
  final String customerName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final credit = ref.read(creditRepositoryProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text('$customerName · Credit history')),
      body: PagedListView<CreditTransaction>(
        fetch: (page) => credit.transactions(customerId, page: page),
        emptyTitle: 'No credit activity yet',
        emptyIcon: Icons.receipt_long_outlined,
        itemBuilder: (context, transaction) {
          final positive = transaction.isOut; // customer now owes more
          final color =
              positive ? scheme.error : successColor(scheme.brightness);
          return AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.label,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        [
                          prettyDateTime(transaction.createdAt),
                          if (transaction.paymentMethod != null)
                            humanizeCode(transaction.paymentMethod),
                          if (transaction.remarks != null &&
                              transaction.remarks!.isNotEmpty)
                            transaction.remarks!,
                        ].whereType<String>().join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${positive ? '+' : '−'} ${money(transaction.amount)}',
                      style: TextStyle(fontWeight: FontWeight.w700, color: color),
                    ),
                    Text(
                      'Bal ${money(transaction.runningBalance)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
