import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/token_store.dart';

/// Light / dark / follow-the-system, chosen in the app and remembered.
///
/// Following the OS is the default because most people set it once for every app
/// on the phone. The override exists because a till doesn't live on a phone in a
/// pocket: a counter tablet under shop lights wants light mode at 9pm even though
/// Android has decided it's night, and a stockroom scanner wants the opposite.
class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._store) : super(_parse(_store.themeMode));

  final TokenStore _store;

  static ThemeMode _parse(String value) => switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _name(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };

  /// Applies immediately and persists in the background.
  ///
  /// The write is deliberately not awaited by the UI: a keystore write is tens of
  /// milliseconds and the whole point of a theme toggle is that the screen changes
  /// the instant it's tapped.
  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    state = mode;
    await _store.setThemeMode(_name(mode));
  }

  /// Re-reads what was loaded from storage — used once, after `TokenStore.load()`
  /// completes at startup, since the controller may have been built before it.
  void syncFromStore() {
    final stored = _parse(_store.themeMode);
    if (stored != state) state = stored;
  }
}
