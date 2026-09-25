import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart'
    show BluetoothInfo;

import '../../core/errors.dart';
import '../../state/providers.dart';

/// Lets the cashier pick a paired/discoverable Bluetooth thermal printer.
///
/// Pops `true` once a printer is connected and remembered in [TokenStore];
/// `null` if dismissed without picking one, so a caller can tell "picked a
/// printer" from "backed out" and decide whether to go on and print.
Future<bool?> showPrinterPicker(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => const _PrinterPickerSheet(),
  );
}

class _PrinterPickerSheet extends ConsumerStatefulWidget {
  const _PrinterPickerSheet();

  @override
  ConsumerState<_PrinterPickerSheet> createState() =>
      _PrinterPickerSheetState();
}

class _PrinterPickerSheetState extends ConsumerState<_PrinterPickerSheet> {
  List<BluetoothInfo>? _devices;
  String? _error;
  bool _scanning = false;
  String? _connectingAddress;

  @override
  void initState() {
    super.initState();
    _scan();
  }

  Future<void> _scan() async {
    setState(() {
      _scanning = true;
      _error = null;
    });
    try {
      final devices = await ref.read(printerServiceProvider).pairedPrinters();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _scanning = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not scan for printers.';
        _scanning = false;
      });
    }
  }

  Future<void> _choose(BluetoothInfo device) async {
    setState(() {
      _connectingAddress = device.macAdress;
      _error = null;
    });
    try {
      await ref.read(printerServiceProvider).connect(device.macAdress);
      await ref
          .read(tokenStoreProvider)
          .setPrinter(device.macAdress, device.name);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _connectingAddress = null;
        _error = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _connectingAddress = null;
        _error = 'Could not connect to that printer.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final devices = _devices;
    final hasDevices = devices != null && devices.isNotEmpty;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Receipt printer',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Scan again',
                  onPressed: _scanning ? null : _scan,
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              "Pair the printer from your phone's Bluetooth settings first "
              "if it doesn't show up here.",
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            if (_scanning && !hasDevices)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (!hasDevices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _error ?? 'No Bluetooth printers found.',
                  style: TextStyle(
                    color: _error != null ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final device = devices[index];
                    final connecting = _connectingAddress == device.macAdress;
                    return ListTile(
                      leading: const Icon(Icons.print_outlined),
                      title: Text(device.name),
                      subtitle: Text(device.macAdress),
                      trailing: connecting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.chevron_right_rounded),
                      onTap:
                          _connectingAddress == null ? () => _choose(device) : null,
                    );
                  },
                ),
              ),
            if (_error != null && hasDevices) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
