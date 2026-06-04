import 'proximity_service.dart';

/// Web target: no BLE radio. Keeps flutter_blue_plus (and dart:io) out of the
/// web compile; the live-vote flow uses only the face-to-face confirmation code.
ProximityService createPlatformProximityService() =>
    const UnsupportedProximityService();
