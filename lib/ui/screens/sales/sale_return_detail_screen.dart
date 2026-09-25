import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/formatters.dart';
import '../../../data/models/sale.dart';
import '../../../data/repositories/catalog_repository.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';

/// A single recorded return — read-only, reached by tapping a tile on the
/// Returns list. There are no lifecycle actions here: once a return is
/// recorded, the refund it carries is final.
class SaleReturnDetailScreen extends ConsumerWidget {
  const SaleReturnDetailScreen({super.key, required this.returnId});

  final String returnId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sales = ref.read(salesRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Return')),
      body: AsyncView<SaleReturn>(
        load: () async {
          var saleReturn = await sales.getReturn(returnId);
          if (saleReturn.needsItemProductLookup) {
            final catalog = ref.read(catalogRepositoryProvider);
            final names = await resolveProductNames(
              catalog,
              saleReturn.items
                  .where((item) => item.needsProductLookup)
                  .map((item) => item.productId ?? ''),
            );
            if (names.isNotEmpty) {
              saleReturn = saleReturn.withItems([
                for (final item in saleReturn.items)
                  if (names[item.productId] case final name?)
                    item.withProductName(name)
                  else
                    item,
              ]);
            }
          }
          return saleReturn;
        },
        builder: (context, saleReturn, reload) =>
            _ReturnBody(saleReturn: saleReturn),
      ),
    );
  }
}

class _ReturnBody extends StatelessWidget {
  const _ReturnBody({required this.saleReturn});

  final SaleReturn saleReturn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      saleReturn.label,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  if (saleReturn.status != null)
                    StatusChip(status: saleReturn.status),
                ],
              ),
              const SizedBox(height: 10),
              DetailRow(
                label: 'Date',
                value: prettyDateTime(saleReturn.createdAt),
              ),
              DetailRow(
                label: 'Sale',
                value: saleReturn.saleNumber ??
                    (saleReturn.saleId != null
                        ? 'Sale #${saleReturn.saleId}'
                        : '—'),
              ),
              if ((saleReturn.reason ?? '').isNotEmpty)
                DetailRow(label: 'Reason', value: saleReturn.reason!),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Items (${saleReturn.items.length})',
          child: Column(
            children: [
              if (saleReturn.items.isEmpty)
                Text(
                  'This return has no line items.',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              for (final item in saleReturn.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.productName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${qty(item.quantity)} returned',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '− ${money(item.refundAmount ?? 0)}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: scheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SectionCard(
          title: 'Refund',
          child: DetailRow(
            label: 'Total refunded',
            value: '− ${money(saleReturn.computedRefund)}',
            valueColor: scheme.error,
            emphasize: true,
          ),
        ),
      ],
    );
  }
}
