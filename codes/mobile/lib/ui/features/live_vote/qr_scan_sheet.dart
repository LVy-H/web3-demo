import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';

/// Sentinel returned by [showQrScanSheet] when the user taps "paste a link"
/// instead of scanning (a value no real QR payload collides with). The caller
/// reacts by opening its paste fallback.
const kQrScanPaste = ' __tessera_paste__';

/// Whether the in-app camera QR scanner can be offered on this platform.
///
/// Checked with `defaultTargetPlatform` from `package:flutter/foundation.dart`
/// (NOT `dart:io`'s `Platform`), because `live_vote_screen.dart` is in the
/// **web** compile graph where `dart:io` is unavailable. The gate returns:
///   - mobile (Android/iOS) → true (native camera path).
///   - web → true: `mobile_scanner` ships a web plugin (`MobileScannerWeb`)
///     using the browser `BarcodeDetector` on Chromium browsers (a ZXing
///     fallback elsewhere). Camera access needs a SECURE CONTEXT (HTTPS or
///     localhost) — satisfied when the app is hosted (e.g. Cloudflare) or run
///     locally — so the live-meeting QR can be scanned from a hosted web client,
///     not just a phone. The paste fallback + [_CameraError] keep voting working
///     if the browser denies the camera or lacks a decoder.
///   - desktop (Linux/Win/macOS) → false (paste is the sole input; mobile_scanner
///     desktop camera support is limited).
bool get cameraScanSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS;

/// Opens the camera QR scanner in a modal sheet and resolves with the first
/// successfully decoded raw barcode value, [kQrScanPaste] if the user chose to
/// paste instead (only when [showPasteAction] is set), or `null` if the user
/// dismisses it / the camera is unavailable / permission denied. The caller does
/// any payload parsing itself — this sheet hands back the raw value.
Future<String?> showQrScanSheet(
  BuildContext context, {
  String title = 'SCAN QR',
  String hint = "Point the camera at the QR. Can't scan? Paste the link instead.",
  bool showPasteAction = false,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Db.void_,
    builder: (_) => _QrScanSheet(
      title: title,
      hint: hint,
      showPasteAction: showPasteAction,
    ),
  );
}

class _QrScanSheet extends StatefulWidget {
  final String title;
  final String hint;
  final bool showPasteAction;
  const _QrScanSheet({
    required this.title,
    required this.hint,
    required this.showPasteAction,
  });
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
        HapticFeedback.mediumImpact(); // success cue
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
                  child: Text(widget.title,
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(widget.hint,
                  style: dbMono(11, Db.muteDim, height: 1.5)),
            ),
            if (widget.showPasteAction)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: TextButton.icon(
                  onPressed: () => Navigator.of(context).pop(kQrScanPaste),
                  icon: const Icon(Icons.keyboard_outlined,
                      size: 16, color: Db.chalkDim),
                  label: Text('PASTE A LINK INSTEAD',
                      style: dbLabel(size: 11, color: Db.chalkDim)),
                ),
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
