import 'proximity_service.dart';
// Native targets pull the dart:io + flutter_blue_plus impl; web gets the no-op
// stub. Keeps the BLE plugin out of the web compile (mirrors proof_service_factory).
import 'proximity_service_stub.dart'
    if (dart.library.io) 'proximity_service_native.dart';

/// The right [ProximityService] for the current platform: Android → BLE beacon
/// scan (radio device-fenced); everything else → no-op (the live-vote flow uses
/// only the face-to-face code there).
ProximityService createProximityService() => createPlatformProximityService();
