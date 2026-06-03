import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';

/// Whether the in-app camera QR scanner can be offered on this platform.
///
/// VERIFIED-OR-FENCED: this is the capability gate. It is intentionally checked
/// with `defaultTargetPlatform` from `package:flutter/foundation.dart` (NOT
/// `dart:io`'s `Platform`), because `live_vote_screen.dart` is in the **web**
/// compile graph and `dart:io` is unavailable there. The gate returns:
///   - mobile (Android/iOS) → true   (camera path offered)
///   - web / desktop (Linux/Win/macOS) → false (paste is the sole input)
/// so the camera affordance is simply absent off-mobile and `mobile_scanner`'s
/// camera code is never instantiated on desktop/web — it can never block or
/// regress the always-available paste-based voting path.
///
/// REAL-DEVICE FOLLOW-UP: the camera scan itself is NOT verified on this host
/// (emulator virtual-camera QR injection is unreliable). The paste fallback is
/// the verified route; live camera scanning is a named real-device follow-up
/// gate. See docs/superpowers/specs/2026-06-02-mobile-scan-and-native-proving-design.md
/// ("Camera scan = real-device / fenced").
bool get cameraScanSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Opens the camera QR scanner in a modal sheet and resolves with the first
/// successfully decoded raw barcode value (or `null` if the user dismisses it
/// or the camera is unavailable / permission denied). The caller feeds the raw
/// value to `LiveVoteViewModel.extractTicket` → `setTicket` → `join` — this
/// sheet does NO ticket parsing of its own.
Future<String?> showQrScanSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Db.void_,
    builder: (_) => const _QrScanSheet(),
  );
}

class _QrScanSheet extends StatefulWidget {
  const _QrScanSheet();
  @override
  State<_QrScanSheet> createState() => _QrScanSheetState();
}

class _QrScanSheetState extends State<_QrScanSheet> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  // `onDetect` can fire repeatedly for the same code; this latch makes sure we
  // pop the sheet and hand the value back exactly once (no stacked joins).
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw != null && raw.trim().isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(raw);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height * 0.6;
    return SafeArea(
      child: SizedBox(
        height: h,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(children: [
                Expanded(
                  child: Text('SCAN QR TICKET',
                      style: dbLabel(size: 11, tracking: 0.16)),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close, color: Db.mute, size: 20),
                  tooltip: 'Close',
                ),
              ]),
            ),
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _CameraError(error: error),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                  'Point the camera at the organizer\'s QR. Can\'t scan? Close '
                  'this and paste the link/ticket instead.',
                  style: dbMono(11, Db.muteDim, height: 1.5)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown inside the scanner when the camera can't be used — most commonly a
/// denied/unavailable camera permission. The sheet stays dismissable so the
/// user falls back to the always-available paste field underneath.
class _CameraError extends StatelessWidget {
  final MobileScannerException error;
  const _CameraError({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied =
        error.errorCode == MobileScannerErrorCode.permissionDenied;
    final msg = denied
        ? 'Camera permission denied. Close this and paste the link/ticket '
            'instead — pasting always works.'
        : 'The camera isn\'t available. Close this and paste the link/ticket '
            'instead.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.no_photography_outlined,
                color: Db.amber, size: 32),
            const SizedBox(height: 14),
            Text(msg,
                textAlign: TextAlign.center,
                style: dbMono(12, Db.chalkDim, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
