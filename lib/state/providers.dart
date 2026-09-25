import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/models/auth.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/credit_repository.dart';
import '../data/repositories/inventory_repository.dart';
import '../data/repositories/notification_repository.dart';
import '../data/repositories/pricing_repository.dart';
import '../data/repositories/purchases_repository.dart';
import '../data/repositories/receipt_format_repository.dart';
import '../data/repositories/sales_repository.dart';
import '../data/token_store.dart';
import '../printing/receipt_printer_service.dart';
import 'notifications.dart';
import 'session.dart';
import 'theme_mode.dart';

// Every provider below is declared with an explicit variable type, not just an
// explicit `Provider<T>(...)` argument. `apiClientProvider` refers to
// `sessionProvider`, which refers back to `apiClientProvider` through the
// repositories, and the compiler will not infer the type of a variable that
// depends on itself ("circularity found during type inference"). The cycle is
// only a *type* cycle — at runtime the session is looked up lazily, inside the
// 401 callback — so annotating the variables is the whole fix.

/// Overridden in `main()` with an instance whose secure storage is already read,
/// so the first frame doesn't have to wait on the keystore.
final Provider<TokenStore> tokenStoreProvider =
    Provider<TokenStore>((ref) => TokenStore());

final Provider<ApiClient> apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    ref.watch(tokenStoreProvider),
    onSessionExpired: () => ref.read(sessionProvider.notifier).onSessionExpired(),
  );
});

final Provider<AuthRepository> authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(apiClientProvider)));

final Provider<CatalogRepository> catalogRepositoryProvider =
    Provider<CatalogRepository>(
        (ref) => CatalogRepository(ref.watch(apiClientProvider)));

final Provider<SalesRepository> salesRepositoryProvider =
    Provider<SalesRepository>(
        (ref) => SalesRepository(ref.watch(apiClientProvider)));

final Provider<PurchasesRepository> purchasesRepositoryProvider =
    Provider<PurchasesRepository>(
        (ref) => PurchasesRepository(ref.watch(apiClientProvider)));

final Provider<PricingRepository> pricingRepositoryProvider =
    Provider<PricingRepository>(
        (ref) => PricingRepository(ref.watch(apiClientProvider)));

final Provider<InventoryRepository> inventoryRepositoryProvider =
    Provider<InventoryRepository>(
        (ref) => InventoryRepository(ref.watch(apiClientProvider)));

final Provider<CreditRepository> creditRepositoryProvider =
    Provider<CreditRepository>(
        (ref) => CreditRepository(ref.watch(apiClientProvider)));

final Provider<ReceiptFormatRepository> receiptFormatRepositoryProvider =
    Provider<ReceiptFormatRepository>(
        (ref) => ReceiptFormatRepository(ref.watch(apiClientProvider)));

final Provider<NotificationRepository> notificationRepositoryProvider =
    Provider<NotificationRepository>(
        (ref) => NotificationRepository(ref.watch(apiClientProvider)));

final StateNotifierProvider<UnreadCountController, int> unreadCountProvider =
    StateNotifierProvider<UnreadCountController, int>(
  (ref) => UnreadCountController(ref.watch(notificationRepositoryProvider)),
);

/// One instance for the app's lifetime — `print_bluetooth_thermal`'s API is
/// static/OS-level (the connection lives in the platform layer, not in this
/// object), so there's nothing here to dispose.
final Provider<ReceiptPrinterService> printerServiceProvider =
    Provider<ReceiptPrinterService>((ref) => ReceiptPrinterService());

final StateNotifierProvider<SessionController, SessionState> sessionProvider =
    StateNotifierProvider<SessionController, SessionState>((ref) {
  return SessionController(
    auth: ref.watch(authRepositoryProvider),
    catalog: ref.watch(catalogRepositoryProvider),
    tokens: ref.watch(tokenStoreProvider),
  );
});

/// The signed-in user, or null when signed out. Screens behind the shell can
/// safely assume this is non-null.
/// Light / dark / system, chosen in Settings and remembered across launches.
final StateNotifierProvider<ThemeModeController, ThemeMode> themeModeProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>(
  (ref) => ThemeModeController(ref.watch(tokenStoreProvider)),
);

final Provider<Me?> meProvider = Provider<Me?>((ref) {
  final state = ref.watch(sessionProvider);
  return switch (state) {
    SessionReady(me: final me) => me,
    SessionNeedsStore(me: final me) => me,
    _ => null,
  };
});

/// The one store every document in this app belongs to.
final Provider<String?> warehouseIdProvider =
    Provider<String?>((ref) => ref.watch(meProvider)?.warehouseId);
