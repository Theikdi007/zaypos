import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/sync/sync_limits.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_text.dart';
import '../products/domain/product_view.dart';

/// Reads one barcode / IMEI with the phone camera. Returns the raw value, or
/// null if the user closed the scanner. Bound to [CameraBarcodeScanner];
/// tests override [barcodeScannerProvider] with a fake.
abstract interface class BarcodeScanner {
  Future<String?> scan(BuildContext context, {String title});
}

/// Camera scanner (mobile_scanner): a full-screen preview that closes on the
/// first code it reads.
class CameraBarcodeScanner implements BarcodeScanner {
  const CameraBarcodeScanner();

  @override
  Future<String?> scan(BuildContext context, {String title = 'Barcode scan'}) =>
      Navigator.of(context, rootNavigator: true).push<String>(
        MaterialPageRoute(fullscreenDialog: true, builder: (_) => _CameraScanScreen(title: title)),
      );
}

final barcodeScannerProvider = Provider<BarcodeScanner>((_) => const CameraBarcodeScanner());

class _CameraScanScreen extends StatefulWidget {
  const _CameraScanScreen({required this.title});
  final String title;

  @override
  State<_CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<_CameraScanScreen> {
  final _controller = MobileScannerController(detectionSpeed: DetectionSpeed.noDuplicates);
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    final value = capture.barcodes.map((b) => b.rawValue).whereType<String>().where((v) => v.trim().isNotEmpty).firstOrNull;
    if (value == null) return;
    _done = true;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(value.trim());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: AppColors.surface,
        title: Text(widget.title, style: AppText.s(17, weight: AppText.w700, color: AppColors.surface)),
        leading: IconButton(
          tooltip: 'ပိတ်ရန်',
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'ကင်မရာ ဖွင့်လို့ မရပါ။ Settings မှာ ကင်မရာ ခွင့်ပြုပါ။',
                  textAlign: TextAlign.center,
                  style: AppText.s(15, color: AppColors.surface),
                ),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 260,
              height: 160,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.surface, width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 48,
            child: Text('Barcode ကို ဘောင်ထဲ ထားပါ',
                textAlign: TextAlign.center, style: AppText.s(15, weight: AppText.w600, color: AppColors.surface)),
          ),
        ],
      ),
    );
  }
}

/// The product with [raw] as its barcode (normalized like the server), or null.
ProductView? productByBarcode(Iterable<ProductView> products, String raw, SyncLimitsData limits) {
  final code = limits.normalize('products.barcode', raw);
  if (code.isEmpty) return null;
  for (final p in products) {
    if (p.product.barcode == code) return p;
  }
  return null;
}

/// Bluetooth / USB barcode scanners in HID (keyboard) mode type the code very
/// fast and end with Enter. This listens to the hardware keyboard while
/// [child] is shown and reports such a burst as one scan; normal typing (slow
/// keys) is ignored. Keys still reach any focused text field.
class HidScannerListener extends StatefulWidget {
  const HidScannerListener({
    super.key,
    required this.onScan,
    required this.child,
    this.maxGap = const Duration(milliseconds: 60),
    this.minLength = 4,
  });

  final ValueChanged<String> onScan;
  final Widget child;

  /// Longer than this between two keys = a person typing, not a scanner.
  final Duration maxGap;

  /// Shorter bursts (e.g. a quick "12" + Enter) are not scans.
  final int minLength;

  @override
  State<HidScannerListener> createState() => _HidScannerListenerState();
}

class _HidScannerListenerState extends State<HidScannerListener> {
  final _buffer = StringBuffer();
  DateTime? _last;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent) return false;
    final now = DateTime.now();
    if (_last != null && now.difference(_last!) > widget.maxGap) _buffer.clear();
    _last = now;
    if (e.logicalKey == LogicalKeyboardKey.enter || e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _buffer.toString();
      _buffer.clear();
      if (code.length >= widget.minLength && mounted) widget.onScan(code);
      return false;
    }
    final ch = e.character;
    if (ch != null && ch.length == 1 && ch.codeUnitAt(0) >= 0x20) _buffer.write(ch);
    return false; // never swallow keys
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
