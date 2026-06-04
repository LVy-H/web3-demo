import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import 'proximity_service.dart';

/// Native factory. Only Android carries the BLE scan; other native targets
/// (desktop / iOS-without-entitlement) are the no-op.
ProximityService createPlatformProximityService() => Platform.isAndroid
    ? AndroidProximityService()
    : const UnsupportedProximityService();

/// BLE proximity attestation — scans for the organizer's beacon (a service UUID
/// both sides derive from the poll address via `bleBeaconUuid`). Voter/central
/// side only: flutter_blue_plus is scan-only, so the organizer *advertising* the
/// beacon needs a physical beacon or a peripheral-mode plugin (a documented
/// follow-up). Device-fenced — no emulator/CI has a BLE radio; every failure
/// resolves to [ProximityResult.none] (the face-to-face code stays the baseline).
class AndroidProximityService implements ProximityService {
  @override
  bool get supported => true; // Android could carry BLE; attest does the real check

  @override
  Future<ProximityResult> attest(String orgBeacon) async {
    StreamSubscription<List<ScanResult>>? sub;
    try {
      if (!await FlutterBluePlus.isSupported) return ProximityResult.none;
      if (FlutterBluePlus.adapterStateNow != BluetoothAdapterState.on) {
        return ProximityResult.none;
      }
      final completer = Completer<ProximityResult>();
      sub = FlutterBluePlus.onScanResults.listen((results) {
        // "near" = the organizer's beacon advertising at a usable RSSI.
        if (results.any((r) => r.rssi > -85) && !completer.isCompleted) {
          completer.complete(
            const ProximityResult(verified: true, method: 'ble'),
          );
        }
      });
      await FlutterBluePlus.startScan(
        withServices: [Guid(orgBeacon)],
        timeout: const Duration(seconds: 6),
      );
      // startScan resolves when its timeout elapses; if nothing matched by then
      // it's a 'none' — proximity is an optional augment, never a blocker.
      return completer.isCompleted
          ? await completer.future
          : ProximityResult.none;
    } catch (_) {
      return ProximityResult.none;
    } finally {
      await sub?.cancel();
      try {
        await FlutterBluePlus.stopScan();
      } catch (_) {}
    }
  }
}
