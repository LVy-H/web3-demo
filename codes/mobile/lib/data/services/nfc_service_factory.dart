import 'nfc_service.dart';
// Native targets pull the dart:io + nfc_manager impl; web gets the no-op stub.
// Keeps the NFC plugin out of the web compile (mirrors proof_service_factory).
import 'nfc_service_stub.dart' if (dart.library.io) 'nfc_service_native.dart';

/// The right [NfcService] for the current platform: Android → real tag writer
/// (radio device-fenced); everything else → no-op (the share sheet shows only
/// the QR there).
NfcService createNfcService() => createPlatformNfcService();
