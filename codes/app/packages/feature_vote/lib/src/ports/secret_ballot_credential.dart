/// Secret-ballot credential acquisition — the voter half of Tessera's
/// RFC 9474 RSABSSA blind-signature flow (system-design §12.2).
///
/// A secret-mode voter, holding only the decision id, turns it into an
/// **anonymous-yet-eligible** credential `(serial, credentialSig)` that they
/// later present at cast time:
///
///   fetch issuer pubkey  (`GET /decisions/:id/issuer`)
///     → verify sha256hex(pem) == the anchored issuerPubKeyHash (trust-minimised)
///     → pick a random 16-byte-hex `serial`
///     → message = `"$decisionId|$serial"`  (binds the credential to THIS decision)
///     → blind(pem, message)  locally
///     → register(decisionId, blinded)  → the issuer blind-signs (sees only the
///       opaque blinded token)
///     → finalize(pem, message, blindSig, state)  → `credentialSig`
///
/// The issuer never sees `(serial, credentialSig)`, so issuance cannot be linked
/// to the eventual ballot from the issued blob (the §6 honest-scope limit is a
/// LIVE host's timing/metadata correlation, not the token). Byte-exact interop
/// with the server's `@cloudflare/blindrsa-ts` is proven by
/// `core_relay/test/server_client_secret_live_test.dart`.
library;

import 'dart:math';

import 'package:core_crypto/credentials/blind_rsa.dart' as blind_rsa;
import 'package:core_relay/server_client.dart';

/// An anonymous secret-ballot credential, ready to cast.
class SecretBallotCredential {
  /// The 16-byte-hex credential serial — the public no-double-vote key (the
  /// public ballot leaf binds it). Anonymous: the issuer never saw it.
  final String serial;

  /// The finalized RSABSSA credential signature over `"$decisionId|$serial"`,
  /// base64 (`randomizer(32) ‖ rawSig`). Presented with [serial] at cast.
  final String credentialSig;

  const SecretBallotCredential({
    required this.serial,
    required this.credentialSig,
  });
}

/// Thrown when a secret-ballot credential cannot be obtained for a reason that
/// is NOT a transport-level [ServerException] (e.g. a tampered issuer key whose
/// hash does not match the anchored commitment).
class SecretBallotCredentialError implements Exception {
  final String message;
  const SecretBallotCredentialError(this.message);
  @override
  String toString() => 'SecretBallotCredentialError: $message';
}

/// Drives the register→blind→finalize handshake against a [ServerClient].
class SecretBallotRegistrar {
  final ServerClient client;
  final Random _rng;

  SecretBallotRegistrar(this.client, {Random? rng})
    : _rng = rng ?? Random.secure();

  /// Obtain a fresh credential for [decisionId].
  ///
  /// [expectedIssuerPubKeyHash] is the anchored hash the client already trusts
  /// (from the public decision view / setupCommitment). When supplied, the
  /// fetched key must match it — defending against a host that serves a
  /// different issuer key from `/issuer` than the one it anchored.
  Future<SecretBallotCredential> obtain(
    String decisionId, {
    String? expectedIssuerPubKeyHash,
  }) async {
    final issuer = await client.getIssuer(decisionId);
    final pem = issuer['issuerPublicKeyPem'];
    final advertisedHash = issuer['issuerPubKeyHash'];
    if (pem is! String || pem.isEmpty || advertisedHash is! String) {
      throw const SecretBallotCredentialError(
        'issuer endpoint did not return a public key',
      );
    }

    // Trust-minimised key fetch: a tampered key is caught BEFORE any blinding.
    final recomputed = blind_rsa.issuerKeyHash(pem);
    if (recomputed != advertisedHash) {
      throw const SecretBallotCredentialError(
        'issuer public-key hash does not match the served hash (tampered key)',
      );
    }
    if (expectedIssuerPubKeyHash != null &&
        expectedIssuerPubKeyHash != advertisedHash) {
      throw const SecretBallotCredentialError(
        'issuer key hash does not match the anchored decision commitment',
      );
    }

    final serial = _randomSerialHex();
    final message = '$decisionId|$serial';
    final blinded = blind_rsa.blind(pem, message);

    final reg = await client.register(decisionId, blinded.blindedB64);
    final blindSig = reg['blindSignature'];
    if (blindSig is! String || blindSig.isEmpty) {
      throw const SecretBallotCredentialError(
        'register did not return a blind signature',
      );
    }

    final credentialSig = blind_rsa.finalize(
      pem,
      message,
      blindSig,
      blinded.state,
    );
    return SecretBallotCredential(serial: serial, credentialSig: credentialSig);
  }

  /// 16 secure-random bytes as lowercase hex (32 chars) — matches the server
  /// e2e's `randomBytes(16).toString('hex')`.
  String _randomSerialHex() {
    final sb = StringBuffer();
    for (var i = 0; i < 16; i++) {
      sb.write(_rng.nextInt(256).toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}
