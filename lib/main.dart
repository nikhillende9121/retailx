import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'data/request_log.dart';
import 'data/token_store.dart';
import 'state/providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Keeps the head of each framework error where it can be read on-device.
  // Debug only; release keeps Flutter's default handler.
  ErrorLog.install();

  // Read the keystore before the first frame so the app can go straight to the
  // right screen instead of flashing the login form at an already-signed-in user.
  final tokens = TokenStore();
  await tokens.load();

  runApp(
    ProviderScope(
      overrides: [tokenStoreProvider.overrideWithValue(tokens)],
      child: const StoreManagerApp(),
    ),
  );
}
