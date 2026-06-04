import 'dart:async';
import 'dart:io' show Platform;

import 'package:nfc_manager/nfc_manager.dart';

import 'nfc_service.dart';

/// Native (mobile/desktop) factory. Only Android carries the radio impl; every
/// other native target is the no-op (desktop/iOS without entitlement).
NfcService createPlatformNfcService() =>
    Platform.isAndroid ? AndroidNfcService() : const UnsupportedNfcService();

/// Writes a `tessera://` poll link to an NFC tag via `nfc_manager`. The radio
/// exchange is **device-fenced** — it needs a real NFC phone + a writable tag,
/// which no emulator/CI box has — so [isAvailable] gates the UI to where it can
/// actually work, and every failure resolves to an [NfcWriteResult] (never
/// throws into the UI).
class AndroidNfcService implements NfcService {
  @override
  Future<bool> isAvailable() async {
    try {
      return await NfcManager.instance.isAvailable();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<NfcWriteResult> writeUrl(String url) async {
    if (!await isAvailable()) return NfcWriteResult.unsupported;
    final completer = Completer<NfcWriteResult>();
    void finish(NfcWriteResult r) {
      if (!completer.isCompleted) completer.complete(r);
    }

    try {
      await NfcManager.instance.startSession(
        onDiscovered: (NfcTag tag) async {
          try {
            final ndef = Ndef.from(tag);
            if (ndef == null || !ndef.isWritable) {
              await NfcManager.instance.stopSession(
                errorMessage: 'This tag is not writable.',
              );
              finish(
                const NfcWriteResult(
                  ok: false,
                  error: 'This tag is read-only — try a writable NFC tag.',
                ),
              );
              return;
            }
            await ndef.write(
              NdefMessage([NdefRecord.createUri(Uri.parse(url))]),
            );
            await NfcManager.instance.stopSession(
              alertMessage: 'Poll written to tag.',
            );
            finish(const NfcWriteResult(ok: true));
          } catch (e) {
            await NfcManager.instance.stopSession(errorMessage: '$e');
            finish(NfcWriteResult(ok: false, error: '$e'));
          }
        },
      );
    } catch (e) {
      finish(NfcWriteResult(ok: false, error: '$e'));
    }
    return completer.future;
  }

  @override
  Future<void> cancel() async {
    try {
      await NfcManager.instance.stopSession();
    } catch (_) {}
  }
}
