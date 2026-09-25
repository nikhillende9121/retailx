import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors.dart';
import '../../../core/formatters.dart';
import '../../../data/models/catalog.dart';
import '../../../data/models/sale.dart';
import '../../../data/models/tenant.dart';
import '../../../printing/default_receipt_schema.dart';
import '../../../state/providers.dart';
import '../../widgets/common.dart';
import '../../widgets/printer_picker_sheet.dart';
import '../shell_screen.dart' show StoreTopBar;
import 'request_log_screen.dart';

/// Profile — the signed-in user, their store/organization, and the settings
/// that belong to this device (printer, theme, diagnostics), not to any one
/// tab in the shop-floor bar.
class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({super.key});

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  TenantProfile? _tenant;
  Warehouse? _warehouse;

  @override
  void initState() {
    super.initState();
    _loadExtraData();
  }

  Future<void> _loadExtraData() async {
    final me = ref.read(meProvider);
    if (me == null) return;
    try {
      final catalog = ref.read(catalogRepositoryProvider);
      final tenantFuture = catalog.tenantProfile();
      final warehouseFuture = me.warehouseId != null
          ? catalog.warehouse(me.warehouseId!)
          : Future<Warehouse?>.value(null);

      final results = await Future.wait([tenantFuture, warehouseFuture]);
      if (!mounted) return;
      setState(() {
        _tenant = results[0] as TenantProfile?;
        _warehouse = results[1] as Warehouse?;
      });
    } catch (_) {}
  }

  void _openRequestLog() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: StoreTopBar(
            title: 'Request log',
            showThemeToggle: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          body: const RequestLogScreen(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(meProvider);
    final session = ref.read(sessionProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    if (me == null) return const LoadingView();

    final companyName = (_tenant?.companyName ?? _tenant?.displayName ?? me.tenantName ?? 'Organization').trim();
    final gstin = (_tenant?.gstNumber ?? '').trim();
    final storeName = (_warehouse?.name ?? me.warehouseName ?? me.storeLabel).trim();
    final storeAddress = (_warehouse?.address ?? me.warehouseAddress ?? '').trim();

    return RefreshIndicator(
      onRefresh: () async {
        await session.refreshMe();
        await _loadExtraData();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 36),
        children: [
          // ── Account: you, your organization, your store ────────────────
          // Merged into one section — a cashier only needs a quick "am I
          // signed in as the right person, at the right store" glance, not
          // three separate cards to scan. Each block stays minimal (name +
          // the one identifying detail), not a full profile dump.
          SectionCard(
            title: 'Account',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  me.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  me.email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    me.roleName ?? 'Staff',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  children: [
                    _LogoTile(
                      imageUrl: me.tenantLogo,
                      fallback: initials(companyName),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            companyName,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            gstin.isNotEmpty ? 'GSTIN $gstin' : 'GSTIN not configured',
                            style: TextStyle(
                              fontSize: 12,
                              color: gstin.isNotEmpty ? scheme.onSurfaceVariant : scheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Text(
                  storeName,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 2),
                Text(
                  storeAddress.isNotEmpty ? storeAddress : 'No address set',
                  style: TextStyle(
                    fontSize: 12,
                    color: storeAddress.isNotEmpty
                        ? scheme.onSurfaceVariant
                        : scheme.error,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Customers moved to the Sales History tab (alongside the sales
          // list itself) — see sales_list_screen.dart.

          // ── Receipt printer ─────────────────────────────────────────────
          _PrinterCard(
            shop: Warehouse(
              id: me.warehouseId ?? 'store_1',
              name: storeName,
              address: storeAddress,
            ),
            tenant: _tenant,
          ),
          const SizedBox(height: 14),

          // ── Appearance ───────────────────────────────────────────────────
          SectionCard(
            title: 'Appearance',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(value: ThemeMode.system, label: Text('System')),
                    ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                    ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                  ],
                  selected: {ref.watch(themeModeProvider)},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      ref.read(themeModeProvider.notifier).set(selection.first),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── App & diagnostics ───────────────────────────────────────────
          SectionCard(
            title: 'App',
            trailing: IconButton(
              tooltip: 'Reload profile',
              onPressed: () async {
                await session.refreshMe();
                await _loadExtraData();
              },
              icon: const Icon(Icons.refresh_rounded),
            ),
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Column(
                    children: [
                      DetailRow(label: 'Application', value: 'RetailX POS v1.0.0'),
                    ],
                  ),
                ),
                // Server API URL — hidden from the cashier-facing profile.
                // Left commented rather than deleted in case a support/debug
                // build wants it back.
                // Padding(
                //   padding: EdgeInsets.fromLTRB(14, 0, 14, 10),
                //   child: DetailRow(label: 'Server API URL', value: session.baseUrl),
                // ),
                // Debug builds only: Android Studio's Network Inspector can't
                // see Flutter traffic, so the app carries its own — a
                // developer diagnostic, not something a cashier needs, so it
                // never shows in a release build.
                if (kDebugMode) ...[
                  const Divider(height: 1),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    leading: Icon(Icons.wifi_tethering_rounded,
                        color: scheme.onSurfaceVariant),
                    title: const Text('Request log'),
                    subtitle: const Text('Every API call this session made'),
                    trailing: Icon(Icons.chevron_right_rounded,
                        color: scheme.onSurfaceVariant),
                    onTap: _openRequestLog,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Plan features & permissions ─────────────────────────────────
          // Hidden — raw feature/permission codes aren't something a cashier
          // needs to see day to day. Left commented rather than deleted in
          // case a support/debug build wants them back.
          // _ChipsExpander(
          //   title: 'Plan features',
          //   values: me.features,
          //   emptyText: 'Server handles feature access per request.',
          // ),
          // const SizedBox(height: 10),
          // _ChipsExpander(
          //   title: 'Permissions',
          //   values: me.permissions,
          //   emptyText: 'No permissions reported.',
          // ),
          // const SizedBox(height: 24),
          const SizedBox(height: 10),

          // ── Sign out ─────────────────────────────────────────────────────
          OutlinedButton.icon(
            onPressed: () async {
              final ok = await confirmAction(
                context,
                title: 'Sign out of RetailX?',
                message: 'You will need your email and password to sign back in.',
                confirmLabel: 'Sign out',
                destructive: true,
              );
              if (ok) await session.logout();
            },
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.error,
              side: BorderSide(color: scheme.error),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tenant's logo, or its initials on a tinted tile when there isn't one —
/// same fallback pattern as [ProductThumb], just square-cornered and sized
/// for a settings row rather than a grid tile.
class _LogoTile extends StatelessWidget {
  const _LogoTile({required this.imageUrl, required this.fallback});

  final String? imageUrl;
  final String fallback;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = imageUrl;
    final placeholder = Center(
      child: Text(
        fallback,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 18,
          color: scheme.primary,
        ),
      ),
    );
    return Container(
      width: 52,
      height: 52,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: (url == null || url.isEmpty)
          ? placeholder
          : Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => placeholder,
            ),
    );
  }
}

class _PrinterCard extends ConsumerStatefulWidget {
  const _PrinterCard({required this.shop, this.tenant});

  final Warehouse shop;
  final TenantProfile? tenant;

  @override
  ConsumerState<_PrinterCard> createState() => _PrinterCardState();
}

class _PrinterCardState extends ConsumerState<_PrinterCard> {
  Future<void> _change() async {
    final picked = await showPrinterPicker(context);
    if (picked == true && mounted) setState(() {});
  }

  Future<void> _forget() async {
    await ref.read(printerServiceProvider).disconnect();
    await ref.read(tokenStoreProvider).clearPrinter();
    if (mounted) setState(() {});
  }

  Future<void> _testPrint() async {
    final printer = ref.read(printerServiceProvider);
    final tokenStore = ref.read(tokenStoreProvider);

    if (tokenStore.printerAddress == null) {
      final picked = await showPrinterPicker(context);
      if (picked != true || !mounted) return;
    }

    final testSale = Sale(
      id: 'TEST-001',
      status: 'CONFIRMED',
      number: 'TEST-001',
      saleDate: DateTime.now().toIso8601String(),
      customerName: 'Test Customer',
      customerPhone: '+91 9876543210',
      items: const [
        SaleItem(
          id: 'item_1',
          productId: 'prod_1',
          productName: 'Sample Product Test',
          quantity: 1,
          price: 100,
          taxes: [
            SaleItemTax(component: 'CGST', ratePercent: 9, amount: 9),
            SaleItemTax(component: 'SGST', ratePercent: 9, amount: 9),
          ],
        ),
      ],
      subtotal: 100,
      taxAmount: 18,
      totalAmount: 118,
    );

    try {
      if (!await printer.isConnected) {
        final address = tokenStore.printerAddress;
        if (address == null) return;
        await printer.connect(address);
      }
      await printer.printWithFormat(
        sale: testSale,
        shop: widget.shop,
        tenant: widget.tenant,
        format: kDefaultReceiptFormat,
      );
      if (!mounted) return;
      showInfoSnack(context, 'Test receipt printed!');
    } on AppError catch (error) {
      if (!mounted) return;
      showErrorSnack(context, error);
    } catch (_) {
      if (!mounted) return;
      showErrorSnack(
        context,
        const AppError(
          code: ErrorCodes.unknown,
          message: 'Could not print test receipt.',
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(tokenStoreProvider).printerName;

    return SectionCard(
      title: 'Receipt printer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DetailRow(label: 'Paired printer', value: name ?? 'Not paired'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _change,
                  icon: const Icon(Icons.print_outlined),
                  label: Text(name == null ? 'Pair a printer' : 'Change printer'),
                ),
              ),
              if (name != null) ...[
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Forget printer',
                  onPressed: _forget,
                  icon: const Icon(Icons.link_off_rounded),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(
            onPressed: _testPrint,
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('Test print receipt'),
          ),
        ],
      ),
    );
  }
}

/// A card of chips that starts collapsed — the feature/permission list can
/// run long and is the least-used part of this screen day to day, so it
/// shouldn't push everything else down by default.
class _ChipsExpander extends StatelessWidget {
  const _ChipsExpander({
    required this.title,
    required this.values,
    required this.emptyText,
  });

  final String title;
  final List<String> values;
  final String emptyText;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Theme(
        // The default ExpansionTile divider clashes with AppCard's own
        // border — this screen doesn't want a second, dimmer rectangle
        // appearing only while the tile is open.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 14),
          childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          title: Text(
            '$title (${values.length})',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          children: [
            values.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      emptyText,
                      style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
                    ),
                  )
                : Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final value in values)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Text(
                            value,
                            style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                          ),
                        ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
