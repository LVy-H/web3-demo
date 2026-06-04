import 'nfc_service.dart';

/// Web target: no NFC. Keeps `nfc_manager` (and dart:io) out of the web compile.
NfcService createPlatformNfcService() => const UnsupportedNfcService();
