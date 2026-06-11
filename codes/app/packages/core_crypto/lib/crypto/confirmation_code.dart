import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:crypto/crypto.dart';

/// Live Meeting Vote — confirmation code derivation.
///
/// Dart port of `codes/frontend/src/lib/confirmationCode.ts`, byte-identical so
/// the voter app, web client, and relayer all derive the same code:
///
///   code = SHA-256( nonceBytes ‖ commitment-as-32-byte-big-endian )
///          → first 16 bits (big-endian) → mod 10000 → zero-padded to 4 digits
///
/// This is part of the cross-client contract (spec §2.5) — do not change the
/// encoding without regenerating the golden vectors.
const int _commitmentBytes = 32;

Uint8List _nonceToBytes(Object nonce) {
  if (nonce is String) {
    final h = nonce.startsWith('0x') ? nonce.substring(2) : nonce;
    return Uint8List.fromList(hex.decode(h));
  }
  if (nonce is Uint8List) return nonce;
  if (nonce is List<int>) return Uint8List.fromList(nonce);
  throw ArgumentError('nonce must be a hex String or bytes');
}

/// Big-endian 32-byte encoding of a non-negative commitment. Semaphore
/// commitments fit in the BN254 field (< 2^254), so 32 bytes always suffices.
Uint8List _commitmentToBytes(Object commitment) {
  final BigInt value;
  if (commitment is BigInt) {
    value = commitment;
  } else if (commitment is String) {
    value = BigInt.parse(commitment);
  } else {
    throw ArgumentError('commitment must be a BigInt or decimal String');
  }
  if (value < BigInt.zero) {
    throw ArgumentError('commitment must be non-negative');
  }
  final out = Uint8List(_commitmentBytes);
  var v = value;
  final mask = BigInt.from(0xff);
  for (var i = _commitmentBytes - 1; i >= 0; i--) {
    out[i] = (v & mask).toInt();
    v = v >> 8;
  }
  if (v != BigInt.zero) {
    throw ArgumentError('commitment exceeds 32 bytes');
  }
  return out;
}

/// Derive the 4-digit confirmation code (e.g. "0427") for a (nonce, commitment)
/// pair. Pure and deterministic. `nonce` is a hex String (with or without 0x)
/// or raw bytes; `commitment` is a [BigInt] or a decimal [String].
String confirmationCode(Object nonce, Object commitment) {
  final input = BytesBuilder()
    ..add(_nonceToBytes(nonce))
    ..add(_commitmentToBytes(commitment));
  final digest = sha256.convert(input.toBytes()).bytes;
  final first16 = (digest[0] << 8) | digest[1];
  return (first16 % 10000).toString().padLeft(4, '0');
}
