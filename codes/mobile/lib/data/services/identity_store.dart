import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the member's Semaphore identity *seed* — the secret string passed to
/// `new Identity(seed)` in the prover. Whoever holds it can vote as this member,
/// so it lives in the platform secure store (Keychain / libsecret / DPAPI /
/// EncryptedSharedPreferences), never in plaintext prefs.
abstract class IdentityStore {
  Future<String?> read();
  Future<void> write(String seed);
  Future<void> delete();
}

/// A fresh 32-byte identity seed as a `0x`-prefixed hex string. `new Identity()`
/// accepts any string; hex keeps it copy/paste-safe and uniform across clients.
String generateIdentitySeed([Random? rng]) {
  final r = rng ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => r.nextInt(256));
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '0x$hex';
}

/// Production store backed by `flutter_secure_storage`.
class SecureIdentityStore implements IdentityStore {
  static const _key = 'tessera.identity.seed';
  final FlutterSecureStorage _s;
  SecureIdentityStore([FlutterSecureStorage? storage])
      : _s = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  @override
  Future<String?> read() => _s.read(key: _key);
  @override
  Future<void> write(String seed) => _s.write(key: _key, value: seed);
  @override
  Future<void> delete() => _s.delete(key: _key);
}

/// In-memory store for tests and previews (no platform channels).
class InMemoryIdentityStore implements IdentityStore {
  String? _seed;
  InMemoryIdentityStore([this._seed]);

  @override
  Future<String?> read() async => _seed;
  @override
  Future<void> write(String seed) async => _seed = seed;
  @override
  Future<void> delete() async => _seed = null;
}
