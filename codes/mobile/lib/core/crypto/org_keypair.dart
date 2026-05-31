import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:convert/convert.dart';
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;

/// Live Meeting Vote — per-poll organizer ticket-signing keypair.
///
/// Dart port of `codes/frontend/src/lib/orgKeypair.ts`. This ed25519 key signs
/// TICKETS and is entirely SEPARATE from the organizer's on-chain wallet. The
/// public half is what the relayer stores (via /tickets/issue) to verify
/// incoming tickets. Persisted per poll under `org-keypair-${pollId}`.
class OrgKeypair {
  /// ed25519 seed, 32-byte hex (no 0x).
  final String privKey;

  /// ed25519 public key, 32-byte hex (no 0x).
  final String pubKey;

  const OrgKeypair({required this.privKey, required this.pubKey});

  Map<String, dynamic> toJson() => {'privKey': privKey, 'pubKey': pubKey};

  static OrgKeypair? fromJson(Object? json) {
    if (json is! Map) return null;
    final priv = json['privKey'];
    final pub = json['pubKey'];
    if (priv is String &&
        pub is String &&
        priv.length == 64 &&
        pub.length == 64) {
      return OrgKeypair(privKey: priv, pubKey: pub);
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is OrgKeypair && other.privKey == privKey && other.pubKey == pubKey;

  @override
  int get hashCode => Object.hash(privKey, pubKey);
}

/// Minimal storage interface the keypair store needs — mirrors the TS
/// `Pick<Storage, 'getItem' | 'setItem' | 'removeItem'>`. Inject a platform
/// implementation (secure storage / shared_preferences) in app code; tests use
/// an in-memory map.
abstract class KeyStore {
  String? getItem(String key);
  void setItem(String key, String value);
  void removeItem(String key);
}

const String _prefix = 'org-keypair-';

String _storageKey(String pollId) => '$_prefix${pollId.toLowerCase()}';

/// Derive the public key (hex) for a given ed25519 seed (hex).
String publicKeyFor(String privKey) {
  final seed = Uint8List.fromList(hex.decode(privKey));
  return hex.encode(ed.public(ed.newKeyFromSeed(seed)).bytes);
}

/// Generate a fresh ed25519 keypair (hex-encoded).
OrgKeypair generateOrgKeypair() {
  final rng = Random.secure();
  final seed = Uint8List(32);
  for (var i = 0; i < 32; i++) {
    seed[i] = rng.nextInt(256);
  }
  final pub = ed.public(ed.newKeyFromSeed(seed)).bytes;
  return OrgKeypair(privKey: hex.encode(seed), pubKey: hex.encode(pub));
}

/// Persist a keypair for a poll. Swallows storage errors (best-effort).
void saveOrgKeypair(String pollId, OrgKeypair kp, KeyStore store) {
  try {
    store.setItem(_storageKey(pollId), jsonEncode(kp.toJson()));
  } catch (_) {
    // best-effort; ignore unavailable/full storage
  }
}

/// Load a poll's keypair, or null if absent/corrupt/unavailable.
OrgKeypair? loadOrgKeypair(String pollId, KeyStore store) {
  try {
    final raw = store.getItem(_storageKey(pollId));
    if (raw == null) return null;
    return OrgKeypair.fromJson(jsonDecode(raw));
  } catch (_) {
    return null;
  }
}

/// Idempotent: return the poll's existing keypair or generate, persist, and
/// return a new one. Same pollId → same key across reloads.
OrgKeypair getOrCreateOrgKeypair(String pollId, KeyStore store) {
  final existing = loadOrgKeypair(pollId, store);
  if (existing != null) return existing;
  final fresh = generateOrgKeypair();
  saveOrgKeypair(pollId, fresh, store);
  return fresh;
}

/// Discard a poll's keypair (e.g. regenerate / key compromise).
void clearOrgKeypair(String pollId, KeyStore store) {
  try {
    store.removeItem(_storageKey(pollId));
  } catch (_) {
    // ignore
  }
}
