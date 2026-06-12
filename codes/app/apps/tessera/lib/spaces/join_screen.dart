// The JOIN surface (R3) — the Kahoot-pattern universal entry (spec §4.1):
// SCAN (capability-gated) / PASTE / TYPE CODE, all feeding feature_join's
// parseJoinInput and routed through THE one JoinTarget → location mapping
// (routing/join_routing.dart). Unrecognized input renders inline inside
// JoinSurface; this screen never navigates to /error for a bad paste.
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:feature_join/feature_join.dart';
import 'package:feature_join/ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../routing/join_routing.dart';
import '../state/app_state.dart';

class JoinScreen extends StatelessWidget {
  /// Test seam: records locations instead of driving the real router.
  /// Production (null) uses `context.go`.
  final void Function(BuildContext context, String location)? navigateOverride;

  /// Test seams forwarded to [JoinSurface] (camera + clipboard).
  final ScanLauncher? scanQr;
  final ClipboardReader? readClipboard;

  const JoinScreen({
    super.key,
    this.navigateOverride,
    this.scanQr,
    this.readClipboard,
  });

  void _open(BuildContext context, JoinTarget target) {
    final location = locationForJoinTarget(target);
    final navigate = navigateOverride;
    if (navigate != null) {
      navigate(context, location);
    } else {
      context.go(location);
    }
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = context.watch<AppState>().capabilities;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: DotGridBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text('JOIN', style: dbSans(34, 800, Db.chalk)),
                const SizedBox(height: 4),
                Text(
                  'POLLS · LIVE SESSIONS · RECEIPTS',
                  style: dbMono(11, Db.segnale),
                ),
                const SizedBox(height: 24),
                JoinSurface(
                  canScanQr: capabilities.canScanQr,
                  onTarget: (target) => _open(context, target),
                  scanQr: scanQr,
                  readClipboard: readClipboard,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
