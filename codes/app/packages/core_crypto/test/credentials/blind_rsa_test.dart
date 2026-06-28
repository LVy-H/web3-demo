import 'dart:convert';
import 'dart:typed_data';

import 'package:core_crypto/credentials/blind_rsa.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit coverage for the pure-Dart RSABSSA-SHA384-PSS-Randomized client.
///
/// Two complementary proofs (the byte-exact interop with the real server is the
/// LIVE e2e, `core_relay/test/server_client_secret_live_test.dart`):
///   1. A full Dart blind → (local RSASP1 blindSign) → finalize → verify
///      round-trip over a fixed RSA-2048 key — exercises EMSA-PSS-ENCODE,
///      blinding, unblinding, and EMSA-PSS-VERIFY end-to-end in Dart.
///   2. A CROSS-IMPL known-answer test: a credential produced by the server's
///      `@cloudflare/blindrsa-ts` (`codes/server/src/credentials/blindrsa.ts`)
///      must verify under the Dart `verifyCredentialLocally` — proving the Dart
///      EMSA-PSS-VERIFY + RSA + MGF1-SHA384 match the library byte-for-byte.
void main() {
  // ── Fixture 1: a fixed RSA-2048 keypair (publicExponent 65537) for the full
  // round-trip. `n`/`d` let the test play the issuer's RSASP1 blind-sign; the
  // SPKI PEM is the same key the public API parses. ──────────────────────────
  const roundTripPem =
      '-----BEGIN PUBLIC KEY-----\n'
      'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA3jaDJmYHL6Isl5i4YSfR\n'
      '56T0Xjs1E7QDZcGRW2F5TnpsSZL+WL6lwAVB7h2Alr7kxr9T9BRI7g4MFFNPDsq9\n'
      'GdGJjF+MbX0eiRYjO3e4CkGjPYfbGosVxsmcmpgj/aOn14dmaNCG7Wy+6+tjUOen\n'
      '1wAhxsfffmDwDOhdI5HfEjvQ/7lwdiRiVQHej8suLAAuubJN+TgUrCTxkkrTzyoR\n'
      'ul0z8lKCXNs1EX7h9er9s7QFajn0KF7uQth0kf4QUqgCtzDZeWO2k3grbPlmvxRY\n'
      'qJR5i2l1f27lmmr4OaOGvUUBYg+sqAIM0NPm0jFxhSy/w0pFv5CRLveyeVEMXJT5\n'
      'PQIDAQAB\n'
      '-----END PUBLIC KEY-----\n';
  final n = BigInt.parse(
    'de36832666072fa22c9798b86127d1e7a4f45e3b3513b40365c1915b61794e7a'
    '6c4992fe58bea5c00541ee1d8096bee4c6bf53f41448ee0e0c14534f0ecabd19'
    'd1898c5f8c6d7d1e8916233b77b80a41a33d87db1a8b15c6c99c9a9823fda3a7'
    'd7876668d086ed6cbeebeb6350e7a7d70021c6c7df7e60f00ce85d2391df123b'
    'd0ffb9707624625501de8fcb2e2c002eb9b24df93814ac24f1924ad3cf2a11ba'
    '5d33f252825cdb35117ee1f5eafdb3b4056a39f4285eee42d87491fe1052a802'
    'b730d97963b693782b6cf966bf1458a894798b69757f6ee59a6af839a386bd45'
    '01620faca8020cd0d3e6d23171852cbfc34a45bf90912ef7b279510c5c94f93d',
    radix: 16,
  );
  final d = BigInt.parse(
    '0edcb0005f360f54462dbc77e67d9a8f26ebf62a79161085e2a623e1ebfec846'
    '2d5c6d61a80f563825d1df4a67598dba70e58688ae5ba35a5aa9f859730891c5'
    'ba8b3bd17f2baa80e293d1b6ee3ea7a6f4b34e9513ad263f75a80cf9ec7c5018'
    '0f74fd9f388531b7827c76719dcd649f1f61e2f0e6cc85d0c05841347a12e49d'
    'ee2682678aff370d4996f1e7e511f37f1829de35bed7db40aafbf3f13a609b45'
    '2c4cb1476e25209cca6888198ac660aa5ef44155d53f9a93d5b49ec34878eb80'
    'f4414c39942e8005c74c4e81e55bb448141eb937d5c46cc6ab7e78b1e2bd0b76'
    'e295485a7cad134e7027a8e7b69a9c7fc172277edf3b14f6e35ecb301ff198f9',
    radix: 16,
  );

  /// The issuer's RSASP1 blind-sign: `s = m^d mod n`, encoded to k=256 bytes.
  /// Mirrors `blindSign` in `blindrsa.ts` (`rsasp1` over the blinded integer).
  Uint8List localBlindSign(Uint8List blinded) {
    var m = BigInt.zero;
    for (final b in blinded) {
      m = (m << 8) | BigInt.from(b & 0xff);
    }
    final s = m.modPow(d, n);
    final out = Uint8List(256);
    var x = s;
    final mask = BigInt.from(0xff);
    for (var i = 255; i >= 0; i--) {
      out[i] = (x & mask).toInt();
      x = x >> 8;
    }
    return out;
  }

  group('RSABSSA-SHA384-PSS-Randomized round-trip (Dart issuer)', () {
    test(
      'blind → blindSign → finalize → verify holds for fresh randomness',
      () {
        // Repeat: fresh randomizer + salt each blind() must still round-trip.
        for (var i = 0; i < 4; i++) {
          final message = 'dec_roundtrip_$i|serial-${i}deadbeefcafe0011';
          final blinded = blind(roundTripPem, message);
          final blindSig = localBlindSign(base64.decode(blinded.blindedB64));
          final credential = finalize(
            roundTripPem,
            message,
            base64.encode(blindSig),
            blinded.state,
          );
          expect(
            verifyCredentialLocally(roundTripPem, message, credential),
            isTrue,
            reason: 'iteration $i must verify',
          );
          // The credential is randomizer(32) ‖ rawSig(256) = 288 bytes.
          expect(base64.decode(credential).length, 288);
        }
      },
    );

    test('a credential does NOT verify under a different message', () {
      const message = 'dec_bind|serial-aabbccddeeff00112233445566778899';
      final blinded = blind(roundTripPem, message);
      final blindSig = localBlindSign(base64.decode(blinded.blindedB64));
      final credential = finalize(
        roundTripPem,
        message,
        base64.encode(blindSig),
        blinded.state,
      );
      expect(
        verifyCredentialLocally(
          roundTripPem,
          'dec_bind|other-serial',
          credential,
        ),
        isFalse,
      );
    });

    test('a tampered credential (flipped byte) verifies false', () {
      const message = 'dec_tamper|serial-00112233445566778899aabbccddeeff';
      final blinded = blind(roundTripPem, message);
      final blindSig = localBlindSign(base64.decode(blinded.blindedB64));
      final credential = finalize(
        roundTripPem,
        message,
        base64.encode(blindSig),
        blinded.state,
      );
      final bytes = base64.decode(credential);
      bytes[bytes.length - 1] ^= 0x01; // flip a signature byte
      expect(
        verifyCredentialLocally(roundTripPem, message, base64.encode(bytes)),
        isFalse,
      );
    });

    test('finalize binds the prepared state to the claimed message', () {
      const message = 'dec_finbind|serial-1234567890abcdef1234567890abcdef';
      final blinded = blind(roundTripPem, message);
      final blindSig = localBlindSign(base64.decode(blinded.blindedB64));
      // Finalizing a DIFFERENT message than was blinded must throw.
      expect(
        () => finalize(
          roundTripPem,
          'dec_finbind|serial-DIFFERENT',
          base64.encode(blindSig),
          blinded.state,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('garbage credential bytes verify false, never throw', () {
      expect(
        verifyCredentialLocally(roundTripPem, 'msg', 'not-base64-@@@'),
        isFalse,
      );
      expect(
        verifyCredentialLocally(
          roundTripPem,
          'msg',
          base64.encode(Uint8List(8)),
        ),
        isFalse,
      );
    });
  });

  group('cross-impl KAT (credential from @cloudflare/blindrsa-ts)', () {
    // Produced by the SERVER's TS library (blind+blindSign+finalize) for a fixed
    // message and per-decision issuer key; regenerate via the genvec script if
    // the protocol changes. Dart MUST accept it byte-for-byte.
    // Built with explicit `\n` (and a trailing `\n`) so the string is
    // byte-identical to the server's PEM — the issuerKeyHash recipe hashes it.
    const katPem =
        '-----BEGIN PUBLIC KEY-----\n'
        'MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAwajNrBwz44aYzod07QcT\n'
        '4D134aBBzuuv5CfZNNF4JMF65FnRJtuqjDoh+v4oCdGJVT3nktPJ3tx6exZTiuN9\n'
        '9H6qJOagY7DXjz3AbO4g2brEYRmQzGSyMKwoWEtGZA7EC3eOOv1CrHfg6WIzSsJe\n'
        'SOw641WxT45HWx8qpJHILwZgs083UnYB4peqSjPexQYeaUN1nR9iOqtH/jE9mfXP\n'
        'uTBycNPYgI4o0/PYkHFobRW6JUH/1prcq5h2LJ7/5Nx4PgPZ8jIb3lv8GOlzq7is\n'
        'trYVCVLXTnHHNBk1Wnia35prSP7TlE2O+BMaUVAv928NtW4IkCMZL6hWQY9HlwuC\n'
        'wwIDAQAB\n'
        '-----END PUBLIC KEY-----\n';
    const katMessage = 'dec_KAT_vector_0001|9f2c4e7a1b6d8f0a2c4e6a8b0d2f4e60';
    const katCredential =
        'eWATcIpxTY5ocZn6I2Yn7HFwmWCKC5G9Y4mYfcv/PwYZh66lHpIPHDZlDw27Ub6gcn4'
        'VPbG02puuU+fYPR94u8/sVczNfKpoVHrMaCDa0VEZzn37WAm02TdMwa0et+jwvXmF5M3'
        'ywMCJ9Jller2EFWWJE5Ai0bGsmLv/gOs9Wh/bzBsBVfmzIaA7rNi7Um+dEExZLZzScn5'
        'kyiCaBOAYUecb4LhtZaDZzGTJtvk2Oun8KZGEH8Q2S7pWA6tYz3cufB28bTdxBjaUwQm'
        '1uu4vSgFZiGp1dn3C9zbJ9qh1Jdxy93kLEQf3LNMcbsvJ0M7g9cQrae+ek9QwVo7/xDU'
        '/L1scL9nXl8OBG/MLKlYuVf46E+1RWKl4dvOrCq+4LiTw';
    const katPubKeyHash =
        '4ddda3d36e85c0157808e5a0d4854c2edc7dae3c9c792b1c6b4f878acf85d2f2';

    test('Dart verifyCredentialLocally accepts the TS-produced credential', () {
      expect(
        verifyCredentialLocally(katPem, katMessage, katCredential),
        isTrue,
      );
    });

    test('the KAT credential fails under a tweaked message', () {
      expect(
        verifyCredentialLocally(katPem, '${katMessage}x', katCredential),
        isFalse,
      );
    });

    test('issuerKeyHash matches the server pubKeyHash recipe', () {
      // sha256hex over the PEM string — exactly issuer.ts `pubKeyHash`.
      expect(issuerKeyHash(katPem), katPubKeyHash);
    });
  });
}
