import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/errors.dart';
import '../../core/formatters.dart';
import '../../data/models/catalog.dart';
import '../../data/models/inventory.dart';
import '../../data/models/paged.dart';
import '../../data/models/purchase.dart';
import '../../data/models/sale.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../state/providers.dart';
import 'common.dart';
import 'paged_list.dart';

/// Generic searchable picker sheet. Everything the store screens need to choose
/// — a product, a customer, a supplier, a past sale, a purchase — is this.
Future<T?> showSearchPicker<T>({
  required BuildContext context,
  required String title,
  required Future<PagedList<T>> Function(int page, String query) fetch,
  required Widget Function(BuildContext context, T item, VoidCallback select)
      itemBuilder,
  String searchHint = 'Search',
  String emptyTitle = 'Nothing found',
  String? emptyMessage,
  Future<T?> Function(BuildContext context)? onCreate,
  String createLabel = 'New',
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _PickerSheet<T>(
      title: title,
      fetch: fetch,
      itemBuilder: itemBuilder,
      searchHint: searchHint,
      emptyTitle: emptyTitle,
      emptyMessage: emptyMessage,
      onCreate: onCreate,
      createLabel: createLabel,
    ),
  );
}

class _PickerSheet<T> extends StatefulWidget {
  const _PickerSheet({
    required this.title,
    required this.fetch,
    required this.itemBuilder,
    required this.searchHint,
    required this.emptyTitle,
    this.emptyMessage,
    this.onCreate,
    this.createLabel = 'New',
  });

  final String title;
  final Future<PagedList<T>> Function(int page, String query) fetch;
  final Widget Function(BuildContext context, T item, VoidCallback select)
      itemBuilder;
  final String searchHint;
  final String emptyTitle;
  final String? emptyMessage;

  /// Lets the sheet create the thing being picked, then select it immediately.
  final Future<T?> Function(BuildContext context)? onCreate;
  final String createLabel;

  @override
  State<_PickerSheet<T>> createState() => _PickerSheetState<T>();
}

class _PickerSheetState<T> extends State<_PickerSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SearchBox(
              hint: widget.searchHint,
              autofocus: false,
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          if (widget.onCreate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final created = await widget.onCreate!(context);
                  if (created != null && context.mounted) {
                    Navigator.of(context).pop(created);
                  }
                },
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(widget.createLabel),
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: PagedListView<T>(
              reloadToken: _query,
              fetch: (page) => widget.fetch(page, _query),
              emptyTitle: widget.emptyTitle,
              emptyMessage: widget.emptyMessage,
              emptyIcon: Icons.search_off_rounded,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
              itemBuilder: (context, item) => widget.itemBuilder(
                context,
                item,
                () => Navigator.of(context).pop(item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Product picker.
///
/// Prefers `/products` (full catalogue, server-side search). If the role can't
/// read the catalogue — a minimal Store Manager role may not hold PRODUCT.VIEW —
/// it falls back to `/inventory/balance`, which is always in scope for this
/// account, and filters client-side.
Future<Product?> pickProduct(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Choose a product',
  // For a warehouse-scoped account, `/products` only returns products
  // price-listed for that warehouse by default — right for choosing what to
  // sell (an unpriced product can't be sold anyway), wrong for choosing what
  // to buy: a purchase is often exactly how a product gets stock for the
  // first time, before it has any retail pricing. Pass true from a purchase
  // flow so newly-acquired, not-yet-priced products still show up — see
  // `CatalogRepository.products`'s `all` param.
  bool includeUnpricedProducts = false,
}) {
  final catalog = ref.read(catalogRepositoryProvider);
  final inventory = ref.read(inventoryRepositoryProvider);
  // Read once, here: the fetch closure below runs again on every page, retry and
  // Load More, and by then the screen that lent us this `ref` may be gone.
  final warehouseId = ref.read(warehouseIdProvider);

  return showSearchPicker<Product>(
    context: context,
    title: title,
    searchHint: 'Name, SKU or barcode',
    fetch: (page, query) async {
      try {
        return await catalog.products(
          page: page,
          search: query,
          all: includeUnpricedProducts,
        );
      } on AppError catch (error) {
        if (error.code == ErrorCodes.permissionDenied ||
            error.code == ErrorCodes.featureNotEnabled ||
            error.code == ErrorCodes.notFound) {
          final balances = await inventory.balance(
            page: page,
            search: query,
            warehouseId: warehouseId,
          );
          final products = balances.items
              .where((balance) => balance.matches(query))
              .map((balance) => balance.product)
              .toList();
          return PagedList<Product>(
            items: products,
            page: balances.page,
            total: balances.total,
            totalPages: balances.totalPages,
          );
        }
        rethrow;
      }
    },
    itemBuilder: (context, product, select) => ListTile(
      onTap: select,
      leading: CircleAvatar(child: Text(initials(product.name))),
      title: Text(product.name),
      subtitle: product.subtitle.isEmpty ? null : Text(product.subtitle),
      trailing: product.defaultPrice == null
          ? null
          : Text(money(product.defaultPrice)),
    ),
  );
}

Future<Customer?> pickCustomer(
  BuildContext context,
  WidgetRef ref, {
  int initialMode = 0,
}) {
  final catalog = ref.read(catalogRepositoryProvider);
  // A group is a property of a customer, so offering one with no CUSTOMER
  // feature would be offering to tag a resource the plan doesn't have.
  final me = ref.read(meProvider);
  final showGroupField =
      (me?.hasFeature(Feature.customer) ?? true) && (me?.hasFeature(Feature.customerGroup) ?? false);
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => _UnifiedCustomerPickerSheet(
      catalog: catalog,
      initialMode: initialMode,
      showGroupField: showGroupField,
    ),
  );
}

/// Customer group chosen on the "New Customer" tab, gated behind
/// CUSTOMER_GROUP — see [pickCustomer]'s [_UnifiedCustomerPickerSheet.showGroupField].
Future<CustomerGroup?> pickCustomerGroup(BuildContext context, WidgetRef ref) {
  final catalog = ref.read(catalogRepositoryProvider);
  return showSearchPicker<CustomerGroup>(
    context: context,
    title: 'Choose a customer group',
    fetch: (page, query) => catalog.customerGroups(page: page, search: query),
    itemBuilder: (context, group, select) => ListTile(
      onTap: select,
      leading: CircleAvatar(child: Text(initials(group.name))),
      title: Text(group.name),
      subtitle: group.code == null ? null : Text(group.code!),
    ),
  );
}

class _UnifiedCustomerPickerSheet extends StatefulWidget {
  const _UnifiedCustomerPickerSheet({
    required this.catalog,
    this.initialMode = 0,
    this.showGroupField = false,
  });

  final CatalogRepository catalog;
  final int initialMode;
  final bool showGroupField;

  @override
  State<_UnifiedCustomerPickerSheet> createState() =>
      _UnifiedCustomerPickerSheetState();
}

class _UnifiedCustomerPickerSheetState
    extends State<_UnifiedCustomerPickerSheet> {
  late int _mode = widget.initialMode; // 0 = Existing, 1 = New
  String _query = '';

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _name = TextEditingController();
  final TextEditingController _phone = TextEditingController();
  final TextEditingController _email = TextEditingController();
  CustomerGroup? _selectedGroup;

  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    super.dispose();
  }

  Future<void> _submitNewCustomer() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final customer = await widget.catalog.createCustomer(
        name: _name.text,
        phone: _phone.text,
        email: _email.text,
        customerGroupId: _selectedGroup?.id,
      );
      if (!mounted) return;
      Navigator.of(context).pop(customer);
    } on AppError catch (failure) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = failure.code == ErrorCodes.permissionDenied ||
                failure.code == ErrorCodes.notFound
            ? "This account can't create customers. Ask an administrator for "
                'the customer-create permission.'
            : failure.uiMessage;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save the customer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;

    return SizedBox(
      height: height,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Select Customer',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SegmentedButton<int>(
                segments: const [
                  ButtonSegment(
                    value: 0,
                    icon: Icon(Icons.person_search_rounded, size: 18),
                    label: Text('Existing'),
                  ),
                  ButtonSegment(
                    value: 1,
                    icon: Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text('New Customer'),
                  ),
                ],
                selected: {_mode},
                showSelectedIcon: false,
                onSelectionChanged: (values) =>
                    setState(() => _mode = values.first),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _mode == 0
                  ? Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: SearchBox(
                            hint: 'Name, phone or email',
                            autofocus: false,
                            onChanged: (value) =>
                                setState(() => _query = value),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: PagedListView<Customer>(
                            reloadToken: _query,
                            fetch: (page) =>
                                widget.catalog.customers(page: page, search: _query),
                            emptyTitle: 'No customer found',
                            emptyMessage:
                                'Switch to New Customer above to add details.',
                            emptyIcon: Icons.search_off_rounded,
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                            itemBuilder: (context, customer) => ListTile(
                              onTap: () => Navigator.of(context).pop(customer),
                              leading: CircleAvatar(
                                child: Text(initials(customer.name)),
                              ),
                              title: Text(customer.name),
                              subtitle: customer.subtitle.isEmpty
                                  ? null
                                  : Text(customer.subtitle),
                              // The group governs which price list/discount
                              // applies to this customer — worth surfacing
                              // right where a cashier picks them, not just
                              // buried in a detail screen.
                              trailing: (widget.showGroupField &&
                                      (customer.customerGroupName ?? '')
                                          .isNotEmpty)
                                  ? Chip(
                                      label: Text(
                                        customer.customerGroupName!,
                                        style: const TextStyle(fontSize: 11),
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _name,
                              autofocus: true,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.next,
                              decoration:
                                  const InputDecoration(labelText: 'Name *'),
                              validator: (value) =>
                                  (value == null || value.trim().isEmpty)
                                      ? 'A name is required'
                                      : null,
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _phone,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              decoration: const InputDecoration(
                                  labelText: 'Phone (optional)'),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _email,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: widget.showGroupField
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              onFieldSubmitted: widget.showGroupField
                                  ? null
                                  : (_) => _submitNewCustomer(),
                              decoration: const InputDecoration(
                                  labelText: 'Email (optional)'),
                            ),
                            if (widget.showGroupField) ...[
                              const SizedBox(height: 12),
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant,
                                  ),
                                ),
                                leading: const Icon(Icons.groups_outlined),
                                title: Text(
                                  _selectedGroup?.name ??
                                      'Customer group (optional)',
                                ),
                                subtitle: _selectedGroup == null
                                    ? const Text(
                                        'Sets which pricing/discount tier applies')
                                    : null,
                                trailing: _selectedGroup == null
                                    ? const Icon(Icons.chevron_right_rounded)
                                    : IconButton(
                                        icon: const Icon(Icons.close_rounded),
                                        onPressed: () => setState(
                                            () => _selectedGroup = null),
                                      ),
                                onTap: () async {
                                  // showSearchPicker directly, not via
                                  // pickCustomerGroup — this sheet already
                                  // has widget.catalog and has no WidgetRef
                                  // of its own to give that helper.
                                  final chosen = await showSearchPicker<CustomerGroup>(
                                    context: context,
                                    title: 'Choose a customer group',
                                    fetch: (page, query) => widget.catalog
                                        .customerGroups(page: page, search: query),
                                    itemBuilder: (context, group, select) => ListTile(
                                      onTap: select,
                                      leading: CircleAvatar(
                                          child: Text(initials(group.name))),
                                      title: Text(group.name),
                                      subtitle: group.code == null
                                          ? null
                                          : Text(group.code!),
                                    ),
                                  );
                                  if (chosen != null) {
                                    setState(() => _selectedGroup = chosen);
                                  }
                                },
                              ),
                            ],
                            if (_error != null) ...[
                              const SizedBox(height: 12),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                ),
                              ),
                            ],
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: _busy ? null : _submitNewCustomer,
                              icon: _busy
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.check_rounded),
                              label: Text(_busy ? 'Saving...' : 'Save & Select'),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<Supplier?> pickSupplier(BuildContext context, WidgetRef ref) {
  final catalog = ref.read(catalogRepositoryProvider);
  return showSearchPicker<Supplier>(
    context: context,
    title: 'Choose a supplier',
    fetch: (page, query) => catalog.suppliers(page: page, search: query),
    itemBuilder: (context, supplier, select) => ListTile(
      onTap: select,
      leading: CircleAvatar(child: Text(initials(supplier.name))),
      title: Text(supplier.name),
      subtitle: supplier.phone == null ? null : Text(supplier.phone!),
    ),
  );
}

/// Sale picker for returns and exchanges. Only sales that can still be returned
/// against are offered; the filter is applied client-side because the list
/// endpoint takes a single status, not a set.
Future<Sale?> pickSale(
  BuildContext context,
  WidgetRef ref, {
  required List<String> allowedStatuses,
  String title = 'Choose a sale',
}) {
  final sales = ref.read(salesRepositoryProvider);
  return showSearchPicker<Sale>(
    context: context,
    title: title,
    searchHint: 'Sale number or customer',
    emptyTitle: 'No eligible sales',
    emptyMessage: 'Only confirmed, delivered or completed sales can be '
        'returned or exchanged.',
    fetch: (page, query) async {
      final result = await sales.list(page: page, search: query);
      final filtered = result.items
          .where((sale) => allowedStatuses.contains(sale.status.toUpperCase()))
          .toList();
      return PagedList<Sale>(
        items: filtered,
        page: result.page,
        pageSize: result.pageSize,
        total: result.total,
        totalPages: result.totalPages,
      );
    },
    itemBuilder: (context, sale, select) => ListTile(
      onTap: select,
      title: Text(sale.label),
      subtitle: Text(
        [
          prettyDate(sale.saleDate ?? sale.createdAt),
          if (sale.customerName != null) sale.customerName!,
        ].join(' · '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(money(sale.computedTotal),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          StatusChip(status: sale.status, dense: true),
        ],
      ),
    ),
  );
}

/// Purchase picker for goods-return-to-supplier. Only received (or partially
/// received) purchases have stock that could go back.
Future<Purchase?> pickPurchase(
  BuildContext context,
  WidgetRef ref, {
  required List<String> allowedStatuses,
}) {
  final purchases = ref.read(purchasesRepositoryProvider);
  return showSearchPicker<Purchase>(
    context: context,
    title: 'Choose a purchase',
    searchHint: 'Purchase number or supplier',
    emptyTitle: 'No eligible purchases',
    emptyMessage: 'Only received purchases can be returned to a supplier.',
    fetch: (page, query) async {
      final result = await purchases.list(page: page, search: query);
      final filtered = result.items
          .where((purchase) =>
              allowedStatuses.contains(purchase.status.toUpperCase()))
          .toList();
      return PagedList<Purchase>(
        items: filtered,
        page: result.page,
        pageSize: result.pageSize,
        total: result.total,
        totalPages: result.totalPages,
      );
    },
    itemBuilder: (context, purchase, select) => ListTile(
      onTap: select,
      title: Text(purchase.label),
      subtitle: Text(
        [
          prettyDate(purchase.purchaseDate ?? purchase.createdAt),
          if (purchase.supplierName != null) purchase.supplierName!,
        ].join(' · '),
      ),
      trailing: StatusChip(status: purchase.status, dense: true),
    ),
  );
}

/// Store picker used only by an unrestricted (tenant-admin) login, where
/// `/auth/me` carries no warehouse and more than one store came back.
Future<Warehouse?> pickWarehouse(
  BuildContext context,
  List<Warehouse> options, {
  String title = 'Choose the destination store',
}) {
  return showModalBottomSheet<Warehouse>(
    context: context,
    useSafeArea: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: options.length,
              itemBuilder: (context, index) {
                final warehouse = options[index];
                return ListTile(
                  leading: const Icon(Icons.store_mall_directory_outlined),
                  title: Text(warehouse.name),
                  subtitle: warehouse.subtitle.isEmpty
                      ? null
                      : Text(warehouse.subtitle),
                  onTap: () => Navigator.of(context).pop(warehouse),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

/// Stock-on-hand picker straight off `/inventory/balance` — used by the stock
/// adjustment and transfer flows, where knowing the current quantity matters.
Future<StockBalance?> pickStockBalance(
  BuildContext context,
  WidgetRef ref, {
  String title = 'Choose a product',
}) {
  final inventory = ref.read(inventoryRepositoryProvider);
  // Read once — see pickProduct: the closure outlives the caller's `ref`.
  final warehouseId = ref.read(warehouseIdProvider);
  return showSearchPicker<StockBalance>(
    context: context,
    title: title,
    searchHint: 'Name or SKU',
    fetch: (page, query) => inventory.balance(
      page: page,
      search: query,
      warehouseId: warehouseId,
    ),
    itemBuilder: (context, balance, select) => ListTile(
      onTap: select,
      leading: CircleAvatar(child: Text(initials(balance.productName))),
      title: Text(balance.productName),
      subtitle: balance.sku == null ? null : Text(balance.sku!),
      trailing: Text(
        '${qty(balance.quantity)} in stock',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: balance.inStock
              ? Theme.of(context).colorScheme.onSurfaceVariant
              : Theme.of(context).colorScheme.error,
        ),
      ),
    ),
  );
}

/// Who to assign a sale to for delivery — shown right before Ship, which now
/// requires an assignee. The list is small and unpaginated (`GET
/// /sales/delivery-assignees`), so it's fetched once up front and filtered
/// client-side as the cashier types, the same fallback pattern
/// `pickProduct`/`pickSale` use for their own client-only filters.
Future<DeliveryAssignee?> pickDeliveryAssignee(
  BuildContext context,
  WidgetRef ref,
) async {
  final sales = ref.read(salesRepositoryProvider);
  final assignees = await sales.deliveryAssignees();
  if (!context.mounted) return null;
  return showSearchPicker<DeliveryAssignee>(
    context: context,
    title: 'Assign a delivery person',
    searchHint: 'Name',
    emptyTitle: 'No one eligible',
    emptyMessage: 'No user in this store can be assigned to deliver.',
    fetch: (page, query) async {
      final filtered = query.isEmpty
          ? assignees
          : assignees
              .where((a) => a.name.toLowerCase().contains(query.toLowerCase()))
              .toList();
      return PagedList<DeliveryAssignee>(
        items: filtered,
        total: filtered.length,
        totalPages: 1,
      );
    },
    itemBuilder: (context, assignee, select) => ListTile(
      onTap: select,
      leading: CircleAvatar(child: Text(initials(assignee.name))),
      title: Text(assignee.name),
    ),
  );
}
