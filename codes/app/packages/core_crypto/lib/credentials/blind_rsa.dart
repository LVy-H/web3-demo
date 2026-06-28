/// Pure-Dart **RFC 9474 RSABSSA-SHA384-PSS-Randomized** blind-signature client.
///
/// This is the Flutter half of Tessera's secret-ballot credential protocol. It
/// must interoperate **byte-for-byte** with the server's
/// `@cloudflare/blindrsa-ts` wrapper (`codes/server/src/credentials/blindrsa.ts`,
/// suite `RSABSSA-SHA384-PSS-Randomized`): the Dart client blinds locally, the
/// server blind-signs with the per-decision issuer private key, the Dart client
/// finalizes, and the server (and any independent verifier) `verifyCredential`s
/// the resulting `(serial, credentialSig)`. If a single byte of the blinding /
/// PSS encoding diverges, the server rejects the cast — so the live e2e
/// (`core_relay/test/server_client_secret_live_test.dart`) is the proof of
/// correctness, not inspection.
///
/// We do NOT use a high-level RSA-PSS signer; EMSA-PSS-ENCODE / -VERIFY and the
/// blinding math are implemented by hand (RFC 8017 §9.1, RFC 9474 §4.1/§5) so
/// the byte layout matches the library exactly:
///   - SHA-384 hash + MGF1-SHA-384 mask (`package:crypto`),
///   - PSS salt length **48** (= hLen; the randomized variant's default),
///   - `emBits = modBits − 1 = 2047`, so the leftmost byte of `EM` is masked to
///     its low 7 bits (encode step 11 / verify's leftmost-bits check),
///   - `EM` / `blinded` / `sig` are fixed-width `k = 256`-byte big-endian,
///   - `prepare()` prepends exactly 32 random bytes; the signature is over
///     `randomizer ‖ message`, never the bare message.
///
/// RSA modexp/modinverse use Dart's native [BigInt]; the SPKI public key is
/// parsed with `pointycastle`'s ASN.1 reader.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/asn1.dart';

/// SHA-384 output length in octets (RFC 9474 SHA384 suite). Also the PSS salt
/// length for the Randomized variant (`sLen = hLen`).
const int _hLen = 48;

/// PSS salt length — the library default for the SHA-384 PSS suite. NOT zero
/// (this is `PSS`, not `PSSZERO`). A mismatch here is the classic interop break.
const int _sLen = 48;

/// The randomizer the Randomized variant's `prepare()` prepends (RFC 9474 §4.1).
/// It is part of the signed message, so the credential ships it (see
/// [finalize]) and the verifier reconstructs `randomizer ‖ message`.
const int _randomizerLen = 32;

final Random _rng = Random.secure();

/// Opaque client blinding state from [blind], consumed by [finalize]. Holds the
/// prepared (randomizer-prefixed) message and the blinding inverse `inv`, both
/// base64 — mirrors the TS `BlindState` so a client can stash it between the two
/// round-trip legs (register, then finalize).
class BlindState {
  /// The prepared message bytes (`randomizer ‖ message`), base64.
  final String preparedB64;

  /// The blinding inverse `r^-1 mod n`, fixed-width 256-byte big-endian, base64.
  final String invB64;

  const BlindState({required this.preparedB64, required this.invB64});
}

/// The output of [blind]: the blinded token to hand the issuer, plus the
/// [BlindState] needed to later unblind the issuer's response.
class BlindResult {
  /// `I2OSP(z, k)` base64 — the blinded message POSTed to `/register`.
  final String blindedB64;
  final BlindState state;

  const BlindResult({required this.blindedB64, required this.state});
}

/// A parsed RSA public key (modulus + public exponent).
class _RsaPub {
  final BigInt n;
  final BigInt e;
  const _RsaPub(this.n, this.e);

  /// Modulus length in octets, `k = ceil(bitLength(n) / 8)` (256 for RSA-2048).
  int get k => (n.bitLength + 7) >> 3;
}

// ── public API (mirrors blindrsa.ts) ───────────────────────────────────────

/// Client step 1. Blind `message` under the issuer's SPKI public key.
///
/// 1. `prepared = randomizer(32) ‖ utf8(message)` (the Randomized `prepare()`).
/// 2. `EM = EMSA-PSS-ENCODE(prepared, emBits = modBits − 1)`; `m = OS2IP(EM)`.
/// 3. random `r ∈ [1, n)` with `gcd(r, n) = 1`; `x = r^e mod n`;
///    `z = (m · x) mod n`; `inv = r^-1 mod n`; `blinded = I2OSP(z, k)`.
BlindResult blind(String spkiPem, String message) {
  final pub = _parseSpki(spkiPem);
  final k = pub.k;
  final emBits = pub.n.bitLength - 1;

  final randomizer = _randomBytes(_randomizerLen);
  final msgBytes = utf8.encode(message);
  final prepared = Uint8List(_randomizerLen + msgBytes.length)
    ..setRange(0, _randomizerLen, randomizer)
    ..setRange(_randomizerLen, _randomizerLen + msgBytes.length, msgBytes);

  final salt = _randomBytes(_sLen);
  final em = _emsaPssEncode(prepared, emBits, salt);
  final m = _os2ip(em);
  if (m.gcd(pub.n) != BigInt.one) {
    // Astronomically unlikely for an RSA modulus; surfaced rather than looped.
    throw StateError('blind: encoded message is not coprime to the modulus');
  }

  // r uniform in [1, n) and coprime to n (RFC 9474 blind steps 6–8).
  BigInt r;
  do {
    r = _os2ip(_randomBytes(k));
  } while (r == BigInt.zero || r >= pub.n || r.gcd(pub.n) != BigInt.one);

  final inv = r.modInverse(pub.n);
  final x = r.modPow(pub.e, pub.n);
  final z = (m * x) % pub.n;

  return BlindResult(
    blindedB64: base64.encode(_i2osp(z, k)),
    state: BlindState(
      preparedB64: base64.encode(prepared),
      invB64: base64.encode(_i2osp(inv, k)),
    ),
  );
}

/// Client step 2. Unblind the issuer's blind signature into a self-contained
/// credential signature over `message`.
///
/// 1. `s = (OS2IP(blindSig) · inv) mod n`; `sig = I2OSP(s, k)`.
/// 2. **Verify** RSASSA-PSS(pub, `prepared`, `sig`) — guards a bad/forged sign.
/// 3. Bind: assert `prepared[32:] == utf8(message)`.
/// 4. `credential = base64( randomizer(32) ‖ sig )` (server splits it back).
String finalize(
  String spkiPem,
  String message,
  String blindSigB64,
  BlindState state,
) {
  final pub = _parseSpki(spkiPem);
  final k = pub.k;

  final prepared = base64.decode(state.preparedB64);
  final inv = _os2ip(base64.decode(state.invB64));
  final blindSig = base64.decode(blindSigB64);
  if (blindSig.length != k) {
    throw StateError('finalize: blind signature is not $k bytes');
  }

  final z = _os2ip(blindSig);
  final s = (z * inv) % pub.n;
  final sig = _i2osp(s, k);

  // Defensive: the verify guards against a non-signature blob from the issuer.
  if (!_rsaPssVerify(pub, prepared, sig)) {
    throw StateError('finalize: unblinded signature failed RSASSA-PSS verify');
  }

  // The state's prepared bytes must be `randomizer ‖ message` for THIS message,
  // so a client cannot blind one message then finalize as another.
  final msgBytes = utf8.encode(message);
  final tail = prepared.sublist(_randomizerLen);
  if (!_constTimeEq(tail, msgBytes)) {
    throw StateError('finalize: message does not match the blinded state');
  }

  final randomizer = prepared.sublist(0, _randomizerLen);
  final credential = Uint8List(_randomizerLen + sig.length)
    ..setRange(0, _randomizerLen, randomizer)
    ..setRange(_randomizerLen, _randomizerLen + sig.length, sig);
  return base64.encode(credential);
}

/// Verify a finalized credential over `message` under the issuer's public key
/// (the unit round-trip / tamper check). The credential is `randomizer(32) ‖
/// rawSig`; we split it, reconstruct `randomizer ‖ message`, and verify the
/// RSASSA-PSS signature. Never throws — any malformed input yields `false`.
bool verifyCredentialLocally(
  String spkiPem,
  String message,
  String credentialB64,
) {
  try {
    final pub = _parseSpki(spkiPem);
    final token = base64.decode(credentialB64);
    if (token.length <= _randomizerLen) return false;
    final randomizer = token.sublist(0, _randomizerLen);
    final rawSig = token.sublist(_randomizerLen);

    final msgBytes = utf8.encode(message);
    final prepared = Uint8List(_randomizerLen + msgBytes.length)
      ..setRange(0, _randomizerLen, randomizer)
      ..setRange(_randomizerLen, _randomizerLen + msgBytes.length, msgBytes);

    return _rsaPssVerify(pub, prepared, Uint8List.fromList(rawSig));
  } catch (_) {
    return false;
  }
}

/// `sha256hex(issuerPublicKeyPem)` — the stable, anchorable issuer-key
/// commitment, computed exactly as the server's `pubKeyHash` (a SHA-256 over the
/// PEM **string** bytes, see `credentials/issuer.ts`). The client recomputes
/// this from `GET /decisions/:id/issuer`'s `issuerPublicKeyPem` and asserts it
/// equals the anchored `issuerPubKeyHash` before blinding.
String issuerKeyHash(String spkiPem) =>
    sha256.convert(utf8.encode(spkiPem)).toString();

// ── EMSA-PSS (RFC 8017 §9.1) ────────────────────────────────────────────────

/// EMSA-PSS-ENCODE(M, emBits) — RFC 8017 §9.1.1, with SHA-384 + MGF1-SHA-384.
/// [salt] is supplied (48 bytes) so the caller controls randomness.
Uint8List _emsaPssEncode(Uint8List msg, int emBits, Uint8List salt) {
  final sLen = salt.length;
  final emLen = (emBits + 7) >> 3;
  final mHash = _sha384(msg);
  // 3. If emLen < hLen + sLen + 2, "encoding error".
  if (emLen < _hLen + sLen + 2) {
    throw StateError('emsa-pss-encode: encoding error (emLen too small)');
  }
  // 5. M' = (0x)00 00 00 00 00 00 00 00 ‖ mHash ‖ salt.
  final mPrime = Uint8List(8 + _hLen + sLen)
    ..setRange(8, 8 + _hLen, mHash)
    ..setRange(8 + _hLen, 8 + _hLen + sLen, salt);
  // 6. H = Hash(M').
  final h = _sha384(mPrime);
  // 8. DB = PS ‖ 0x01 ‖ salt, length emLen - hLen - 1.
  final psLen = emLen - sLen - _hLen - 2;
  final db = Uint8List(emLen - _hLen - 1);
  db[psLen] = 0x01;
  db.setRange(psLen + 1, psLen + 1 + sLen, salt);
  // 9–10. maskedDB = DB ⊕ MGF1(H, emLen - hLen - 1).
  final dbMask = _mgf1(h, emLen - _hLen - 1);
  final maskedDb = Uint8List(db.length);
  for (var i = 0; i < db.length; i++) {
    maskedDb[i] = db[i] ^ dbMask[i];
  }
  // 11. Zero the leftmost 8·emLen − emBits bits of maskedDB[0].
  maskedDb[0] &= 0xff >> (8 * emLen - emBits);
  // 12. EM = maskedDB ‖ H ‖ 0xbc.
  final em = Uint8List(emLen);
  em.setRange(0, maskedDb.length, maskedDb);
  em.setRange(maskedDb.length, maskedDb.length + _hLen, h);
  em[emLen - 1] = 0xbc;
  return em;
}

/// EMSA-PSS-VERIFY(M, EM, emBits) — RFC 8017 §9.1.2 (SHA-384, sLen = 48).
bool _emsaPssVerify(Uint8List msg, Uint8List em, int emBits) {
  final emLen = (emBits + 7) >> 3;
  final mHash = _sha384(msg);
  if (emLen < _hLen + _sLen + 2) return false;
  if (em[emLen - 1] != 0xbc) return false;

  final maskedDb = em.sublist(0, emLen - _hLen - 1);
  final h = em.sublist(emLen - _hLen - 1, emLen - 1);

  // Leftmost 8·emLen − emBits bits of maskedDB[0] must be zero.
  final bitsToClear = 8 * emLen - emBits;
  final topMask = (0xff << (8 - bitsToClear)) & 0xff;
  if ((maskedDb[0] & topMask) != 0) return false;

  final dbMask = _mgf1(h, emLen - _hLen - 1);
  final db = Uint8List(maskedDb.length);
  for (var i = 0; i < db.length; i++) {
    db[i] = maskedDb[i] ^ dbMask[i];
  }
  // Clear the same leftmost bits in the recovered DB.
  db[0] &= 0xff >> bitsToClear;

  // PS (emLen − hLen − sLen − 2 zero octets) ‖ 0x01.
  final psLen = emLen - _hLen - _sLen - 2;
  for (var i = 0; i < psLen; i++) {
    if (db[i] != 0) return false;
  }
  if (db[psLen] != 0x01) return false;

  final salt = db.sublist(db.length - _sLen);
  final mPrime = Uint8List(8 + _hLen + _sLen)
    ..setRange(8, 8 + _hLen, mHash)
    ..setRange(8 + _hLen, 8 + _hLen + _sLen, salt);
  final hPrime = _sha384(mPrime);
  return _constTimeEq(h, hPrime);
}

/// RSASSA-PSS-VERIFY (RFC 8017 §8.1.2): recover `EM = I2OSP(sig^e mod n, emLen)`
/// then run EMSA-PSS-VERIFY over `emBits = modBits − 1`.
bool _rsaPssVerify(_RsaPub pub, Uint8List msg, Uint8List sig) {
  final k = pub.k;
  if (sig.length != k) return false;
  final s = _os2ip(sig);
  if (s >= pub.n) return false;
  final m = s.modPow(pub.e, pub.n);
  final modBits = pub.n.bitLength;
  final emBits = modBits - 1;
  final emLen = (emBits + 7) >> 3;
  final em = _i2osp(m, emLen);
  return _emsaPssVerify(msg, em, emBits);
}

/// MGF1 (RFC 8017 Appendix B.2.1) over SHA-384.
Uint8List _mgf1(Uint8List seed, int maskLen) {
  final out = BytesBuilder(copy: false);
  final counter = Uint8List(4);
  var c = 0;
  while (out.length < maskLen) {
    counter[0] = (c >> 24) & 0xff;
    counter[1] = (c >> 16) & 0xff;
    counter[2] = (c >> 8) & 0xff;
    counter[3] = c & 0xff;
    final block = Uint8List(seed.length + 4)
      ..setRange(0, seed.length, seed)
      ..setRange(seed.length, seed.length + 4, counter);
    out.add(_sha384(block));
    c++;
  }
  return out.toBytes().sublist(0, maskLen);
}

// ── byte / bigint helpers ───────────────────────────────────────────────────

Uint8List _sha384(List<int> data) =>
    Uint8List.fromList(sha384.convert(data).bytes);

/// OS2IP — big-endian unsigned bytes → non-negative [BigInt].
BigInt _os2ip(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b & 0xff);
  }
  return r;
}

/// I2OSP — non-negative [BigInt] → fixed-width big-endian octet string. Throws
/// if `n` does not fit in [length] bytes (RFC 8017 §4.1).
Uint8List _i2osp(BigInt n, int length) {
  if (n.isNegative) throw ArgumentError('i2osp: negative integer');
  final out = Uint8List(length);
  var x = n;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (x & mask).toInt();
    x = x >> 8;
  }
  if (x != BigInt.zero) {
    throw ArgumentError('i2osp: integer does not fit in $length bytes');
  }
  return out;
}

Uint8List _randomBytes(int n) {
  final b = Uint8List(n);
  for (var i = 0; i < n; i++) {
    b[i] = _rng.nextInt(256);
  }
  return b;
}

/// Length-independent constant-time-ish equality (no early-out on the first
/// mismatched byte). Returns false on length mismatch.
bool _constTimeEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

// ── SPKI PEM parse ──────────────────────────────────────────────────────────

/// Parse an SPKI (SubjectPublicKeyInfo) PEM RSA public key into `(n, e)`.
///
/// `SubjectPublicKeyInfo ::= SEQUENCE { AlgorithmIdentifier, BIT STRING }`,
/// whose BIT STRING wraps `RSAPublicKey ::= SEQUENCE { modulus, publicExponent }`.
_RsaPub _parseSpki(String pem) {
  final der = _pemToDer(pem);
  final spki = ASN1Parser(der).nextObject() as ASN1Sequence;
  final bitString = spki.elements![1] as ASN1BitString;
  final inner = Uint8List.fromList(bitString.stringValues!);
  final rsaSeq = ASN1Parser(inner).nextObject() as ASN1Sequence;
  final n = (rsaSeq.elements![0] as ASN1Integer).integer!;
  final e = (rsaSeq.elements![1] as ASN1Integer).integer!;
  return _RsaPub(n, e);
}

Uint8List _pemToDer(String pem) {
  final b64 = pem
      .split('\n')
      .where((l) => !l.startsWith('-----'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .join();
  return base64.decode(b64);
}
