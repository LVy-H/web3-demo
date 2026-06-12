/// Camera QR sheet for the JOIN surface and the live-voter ticket entry.
///
/// Ported from the proven `codes/mobile` `qr_scan_sheet.dart` onto the
/// design_system tokens. The sheet hands back the FIRST decoded raw value
/// (or `null` on dismiss / camera failure) — all parsing stays with the
/// caller, which feeds it through `parseJoinInput`.
library;

import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:mobile_scanner/mobile_scanner.dart';

/// Opens the camera QR scanner in a modal sheet and resolves with the first
/// successfully decoded raw barcode value, or `null` if the user dismisses
/// it / the camera is unavailable / permission was denied. Callers only
/// offer this when `Capabilities.canScanQr` — the JOIN surface leads with
/// paste/code everywhere else (spec §4.3).
Future<String?> showJoinScanSheet(
  BuildContext context, {
  String title = 'SCAN THE INVITE',
  String hint =
      "Point the camera at the QR. Can't scan? "
      'Close this and paste the link instead.',
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Db.void_,
    builder: (_) => _JoinScanSheet(title: title, hint: hint),
  );
}

class _JoinScanSheet extends StatefulWidget {
  final String title;
  final String hint;

  const _JoinScanSheet({required this.title, required this.hint});

  @override
  State<_JoinScanSheet> createState() => _JoinScanSheetState();
}

class _JoinScanSheetState extends State<_JoinScanSheet> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );

  // `onDetect` can fire repeatedly for the same code; this latch pops the
  // sheet and hands the value back exactly once (no stacked joins).
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
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: dbLabel(size: 11, tracking: 0.16),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Db.mute, size: 20),
                    tooltip: 'Close',
                  ),
                ],
              ),
            ),
            Expanded(
              child: MobileScanner(
                controller: _controller,
                onDetect: _onDetect,
                errorBuilder: (context, error) => _CameraError(error: error),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Text(
                widget.hint,
                style: dbMono(11, Db.muteDim, height: 1.5),
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
/// user falls back to the always-available paste/code entry underneath.
class _CameraError extends StatelessWidget {
  final MobileScannerException error;

  const _CameraError({required this.error});

  @override
  Widget build(BuildContext context) {
    final denied = error.errorCode == MobileScannerErrorCode.permissionDenied;
    final msg = denied
        ? 'Camera permission denied. Close this and paste the link '
              'instead — pasting always works.'
        : "The camera isn't available. Close this and paste the link "
              'instead.';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Db.amber,
              size: 32,
            ),
            const SizedBox(height: 14),
            Text(
              msg,
              textAlign: TextAlign.center,
              style: dbMono(12, Db.chalkDim, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
