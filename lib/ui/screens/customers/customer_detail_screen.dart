import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants.dart';
import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/credit.dart';
import '../../../state/providers.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'credit_transactions_screen.dart';

/// One customer: contact info, and — when the tenant has credit enabled and
/// this account can see it — their credit standing, with actions to collect
/// a payment, review the full ledger, or adjust the credit settings
/// themselves. See `credit_androidChanges.md` §4/§5/§7.
class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen> {
  int _reload = 0;

  Future<(Customer, CreditConfig?)> _load() async {
    final catalog = ref.read(catalogRepositoryProvider);
    final me = ref.read(meProvider);
    final customer = await catalog.customer(widget.customerId);
    if (customer == null) {
      throw const AppError(
        code: ErrorCodes.notFound,
        message: 'Customer not found.',
      );
    }

    CreditConfig? config;
    // Best-effort: missing CREDIT.VIEW on an otherwise credit-enabled
    // tenant (or any other failure) just hides the card — the customer's
    // own info still shows.
    if (me?.hasFeature(Feature.creditPayment) ?? false) {
      try {
        config =
            await ref.read(creditRepositoryProvider).config(widget.customerId);
      } catch (_) {}
    }
    return (customer, config);
  }

  Future<void> _collectPayment(CreditConfig config) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => _CollectPaymentSheet(customerId: config.customerId),
    );
    if (result == true && mounted) setState(() => _reload++);
  }

  Future<void> _editCreditSettings(CreditConfig config) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _CreditSettingsDialog(config: config),
    );
    if (changed == true && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Customer')),
      body: AsyncView<(Customer, CreditConfig?)>(
        reloadToken: _reload,
        load: _load,
        builder: (context, data, reload) {
          final customer = data.$1;
          final config = data.$2;
          final canManageCredit = me?.can(Perm.creditManage) ?? false;
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
                        CircleAvatar(child: Text(initials(customer.name))),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            customer.name,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (customer.phone != null)
                      DetailRow(label: 'Phone', value: customer.phone!),
                    if (customer.email != null)
                      DetailRow(label: 'Email', value: customer.email!),
                    if (customer.customerGroupName != null)
                      DetailRow(label: 'Group', value: customer.customerGroupName!),
                  ],
                ),
              ),
              if (config != null) ...[
                const SizedBox(height: 10),
                SectionCard(
                  title: 'Credit',
                  trailing: canManageCredit
                      ? IconButton(
                          tooltip: 'Edit credit settings',
                          onPressed: () => _editCreditSettings(config),
                          icon: const Icon(Icons.tune_rounded),
                        )
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DetailRow(
                        label: 'Current due',
                        value: money(config.currentBalance),
                        emphasize: true,
                        valueColor: config.currentBalance > 0
                            ? scheme.error
                            : successColor(scheme.brightness),
                      ),
                      DetailRow(
                        label: 'Credit limit',
                        value: config.creditLimit == null
                            ? 'No limit set'
                            : money(config.creditLimit!),
                      ),
                      if (config.settlementDay != null)
                        DetailRow(
                          label: 'Settlement day',
                          value: 'Day ${config.settlementDay} of the month',
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (canManageCredit) ...[
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _collectPayment(config),
                                icon: const Icon(Icons.payments_outlined),
                                label: const Text('Collect payment'),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CreditTransactionsScreen(
                                    customerId: config.customerId,
                                    customerName: config.customerName,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('History'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _CollectPaymentSheet extends ConsumerStatefulWidget {
  const _CollectPaymentSheet({required this.customerId});

  final String customerId;

  @override
  ConsumerState<_CollectPaymentSheet> createState() =>
      _CollectPaymentSheetState();
}

class _CollectPaymentSheetState extends ConsumerState<_CollectPaymentSheet> {
  final _amount = TextEditingController();
  final _remarks = TextEditingController();
  String _method = kPaymentMethods.first;
  bool _busy = false;
  String? _amountError;

  @override
  void dispose() {
    _amount.dispose();
    _remarks.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter an amount greater than zero');
      return;
    }
    setState(() {
      _amountError = null;
      _busy = true;
    });
    try {
      await ref.read(creditRepositoryProvider).recordPayment(
            widget.customerId,
            amount: amount,
            paymentMethod: _method,
            remarks: _remarks.text,
          );
      if (!mounted) return;
      showInfoSnack(context, 'Payment recorded.');
      Navigator.of(context).pop(true);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(context, error);
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not record the payment.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Collect payment', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              TextField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: '₹ ',
                  labelText: 'Amount',
                  errorText: _amountError,
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Received by',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final method in kPaymentMethods)
                    ChoiceChip(
                      label: Text(humanizeCode(method)),
                      selected: _method == method,
                      onSelected: (_) => setState(() => _method = method),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _remarks,
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Remarks (optional)',
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Record payment'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreditSettingsDialog extends ConsumerStatefulWidget {
  const _CreditSettingsDialog({required this.config});

  final CreditConfig config;

  @override
  ConsumerState<_CreditSettingsDialog> createState() =>
      _CreditSettingsDialogState();
}

class _CreditSettingsDialogState extends ConsumerState<_CreditSettingsDialog> {
  late final TextEditingController _limit = TextEditingController(
    text: widget.config.creditLimit?.toStringAsFixed(2) ?? '',
  );
  late final TextEditingController _settlementDay = TextEditingController(
    text: widget.config.settlementDay?.toString() ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _limit.dispose();
    _settlementDay.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final limitText = _limit.text.trim();
    final limit = limitText.isEmpty ? null : double.tryParse(limitText);
    if (limitText.isNotEmpty && limit == null) {
      setState(() => _error = 'Enter a valid limit, or leave it blank for no limit');
      return;
    }
    final dayText = _settlementDay.text.trim();
    int? day;
    if (dayText.isNotEmpty) {
      day = int.tryParse(dayText);
      if (day == null || day < 1 || day > 28) {
        setState(() => _error = 'Settlement day must be between 1 and 28');
        return;
      }
    }

    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      await ref.read(creditRepositoryProvider).updateConfig(
            widget.config.customerId,
            creditLimit: limit,
            settlementDay: day,
          );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = error.uiMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save credit settings.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Credit settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _limit,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              prefixText: '₹ ',
              labelText: 'Credit limit',
              helperText: 'Leave blank for no limit',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _settlementDay,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Settlement day',
              helperText: 'Day of the month, 1–28',
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
