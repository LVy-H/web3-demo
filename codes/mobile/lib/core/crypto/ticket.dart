import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// Live Meeting Vote — signed, expiring tickets.
///
/// Dart port of `codes/frontend/src/lib/ticket.ts`. The relayer verifies the
/// same byte layout, so this encoding is the cross-client contract (spec §2.5)
/// — do not change it casually.
///
/// Canonical preimage (what gets signed) is a FIXED-WIDTH 32-byte buffer:
///   [ pollId 20 bytes ][ nonce 8 bytes ][ expiresAt uint32 big-endian 4 bytes ]
/// Wire form = base64url-nopad( preimage(32) ‖ ed25519 signature(64) ) = 96 bytes.

/// Seconds a ticket stays valid after issuance.
const int ticketTtlSeconds = 30;

const int _addrBytes = 20;
const int _nonceBytes = 8;
const int _expBytes = 4;
const int _preimageBytes = _addrBytes + _nonceBytes + _expBytes; // 32
const int _sigBytes = 64;
const int _wireBytes = _preimageBytes + _sigBytes; // 96

enum TicketInvalidReason { malformed, badSig, expired }

/// The decoded, unsigned ticket fields.
class Ticket {
  /// Poll address, 0x-prefixed lowercase hex (the M1 poll / clone address).
  final String p;

  /// Single-use nonce, 8 random bytes as hex (no 0x).
  final String n;

  /// Expiry, unix seconds.
  final int e;

  const Ticket({required this.p, required this.n, required this.e});

  @override
  bool operator ==(Object other) =>
      other is Ticket && other.p == p && other.n == n && other.e == e;

  @override
  int get hashCode => Object.hash(p, n, e);

  @override
  String toString() => 'Ticket(p: $p, n: $n, e: $e)';
}

/// Result of [verifyTicket]: either valid with the decoded ticket, or invalid
/// with a [TicketInvalidReason] (and the decoded ticket when it parsed but the
/// expiry lapsed).
class VerifyResult {
  final bool valid;
  final TicketInvalidReason? reason;
  final Ticket? ticket;

  const VerifyResult.valid(this.ticket)
      : valid = true,
        reason = null;

  const VerifyResult.invalid(this.reason, [this.ticket]) : valid = false;
}

String _stripHex(String h) =>
    (h.startsWith('0x') || h.startsWith('0X')) ? h.substring(2) : h;

Uint8List _keyToBytes(Object key) {
  if (key is String) return Uint8List.fromList(hex.decode(_stripHex(key)));
  if (key is Uint8List) return key;
  if (key is List<int>) return Uint8List.fromList(key);
  throw ArgumentError('key must be a hex String or bytes');
}

String _b64UrlNoPad(Uint8List bytes) =>
    base64Url.encode(bytes).replaceAll('=', '');

/// Decode a base64url string that may lack padding (and reject non-url alphabet
/// / junk via [FormatException], which callers translate to "malformed").
Uint8List _b64UrlDecode(String s) => base64Url.decode(base64Url.normalize(s));

/// Build a fresh (unsigned) ticket payload for a poll. `now` is injected (unix
/// seconds) so callers/tests stay deterministic.
Ticket createTicketPayload(String pollId, int now,
    {int ttlSeconds = ticketTtlSeconds}) {
  final addr = _stripHex(pollId).toLowerCase();
  if (addr.length != _addrBytes * 2 || !RegExp(r'^[0-9a-f]+$').hasMatch(addr)) {
    throw ArgumentError(
        'invalid pollId: expected 20-byte hex address, got $pollId');
  }
  final rng = Random.secure();
  final nonce = Uint8List(_nonceBytes);
  for (var i = 0; i < _nonceBytes; i++) {
    nonce[i] = rng.nextInt(256);
  }
  return Ticket(p: '0x$addr', n: hex.encode(nonce), e: now + ttlSeconds);
}

/// The 32-byte canonical preimage that gets signed. Byte-for-byte reproducible
/// by the relayer and web client.
Uint8List ticketPreimage(Ticket t) {
  final addr = hex.decode(_stripHex(t.p));
  if (addr.length != _addrBytes) throw ArgumentError('invalid pollId length');
  final nonce = hex.decode(t.n);
  if (nonce.length != _nonceBytes) throw ArgumentError('invalid nonce length');
  if (t.e < 0 || t.e > 0xffffffff) throw ArgumentError('invalid expiry');
  final out = Uint8List(_preimageBytes);
  out.setRange(0, _addrBytes, addr);
  out.setRange(_addrBytes, _addrBytes + _nonceBytes, nonce);
  ByteData.sublistView(out, _addrBytes + _nonceBytes, _preimageBytes)
      .setUint32(0, t.e, Endian.big);
  return out;
}

/// Sign a ticket payload with the organizer's ed25519 private key (32-byte seed
/// hex or bytes). Returns the base64url-nopad wire string carried in the QR.
String signTicket(Ticket t, Object privKey) {
  final seed = _keyToBytes(privKey);
  final pk = ed.newKeyFromSeed(seed);
  final preimage = ticketPreimage(t);
  final sig = ed.sign(pk, preimage);
  final wire = Uint8List(_wireBytes);
  wire.setRange(0, _preimageBytes, preimage);
  wire.setRange(_preimageBytes, _wireBytes, sig);
  return _b64UrlNoPad(wire);
}

/// Parse the wire string back into ticket fields. Does NOT verify the signature
/// — use [verifyTicket] for that. Throws on malformed input.
Ticket decodeTicket(String encoded) {
  final wire = _b64UrlDecode(encoded);
  if (wire.length != _wireBytes) {
    throw ArgumentError(
        'malformed ticket: expected $_wireBytes bytes, got ${wire.length}');
  }
  final addr = wire.sublist(0, _addrBytes);
  final nonce = wire.sublist(_addrBytes, _addrBytes + _nonceBytes);
  final e = ByteData.sublistView(wire, _addrBytes + _nonceBytes, _preimageBytes)
      .getUint32(0, Endian.big);
  return Ticket(p: '0x${hex.encode(addr)}', n: hex.encode(nonce), e: e);
}

/// Verify a wire ticket against the organizer's public key. `now` (unix seconds)
/// is injected so tests are deterministic; defaults to the current time.
VerifyResult verifyTicket(String encoded, Object pubKey, {int? now}) {
  final ts = now ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
  Uint8List wire;
  try {
    wire = _b64UrlDecode(encoded);
  } catch (_) {
    return const VerifyResult.invalid(TicketInvalidReason.malformed);
  }
  if (wire.length != _wireBytes) {
    return const VerifyResult.invalid(TicketInvalidReason.malformed);
  }

  final preimage = wire.sublist(0, _preimageBytes);
  final sig = wire.sublist(_preimageBytes, _wireBytes);

  bool sigOk;
  try {
    sigOk = ed.verify(ed.PublicKey(_keyToBytes(pubKey)), preimage, sig);
  } catch (_) {
    return const VerifyResult.invalid(TicketInvalidReason.badSig);
  }
  if (!sigOk) return const VerifyResult.invalid(TicketInvalidReason.badSig);

  Ticket ticket;
  try {
    ticket = decodeTicket(encoded);
  } catch (_) {
    return const VerifyResult.invalid(TicketInvalidReason.malformed);
  }
  if (ticket.e <= ts) {
    return VerifyResult.invalid(TicketInvalidReason.expired, ticket);
  }
  return VerifyResult.valid(ticket);
}
