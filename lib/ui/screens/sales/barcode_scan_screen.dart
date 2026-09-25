import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera scanner. Pops with the first barcode's raw value, or
/// nothing if the cashier backs out.
class BarcodeScanScreen extends StatefulWidget {
  const BarcodeScanScreen({super.key});

  @override
  State<BarcodeScanScreen> createState() => _BarcodeScanScreenState();
}

class _BarcodeScanScreenState extends State<BarcodeScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  // The controller keeps streaming detections while the pop animation plays,
  // and a second hit mid-animation would pop the route twice.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _handled = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan a barcode'),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) => Icon(
                state.torchState == TorchState.on
                    ? Icons.flash_on_rounded
                    : Icons.flash_off_rounded,
              ),
            ),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: MobileScanner(
        controller: _controller,
        onDetect: _onDetect,
        errorBuilder: (context, error, child) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              error.errorDetails?.message ??
                  "Couldn't reach the camera. Check the camera permission "
                      'for this app.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

extension on List<Barcode> {
  Barcode? get firstOrNull => isEmpty ? null : first;
}
