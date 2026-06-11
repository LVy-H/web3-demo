import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Remembers which polls THIS device created. Under the wallet-free model the
/// relayer is the on-chain `creator` of every sponsored poll, so "polls I made"
/// can't be derived from the chain — it's a local record, written when a create
/// succeeds and read by the browse "MINE" filter. Addresses are stored
/// lowercased for case-insensitive matching. Not secret, but it rides the same
/// secure store as the identity seed to avoid adding a prefs dependency.
abstract class CreatedPollsStore {
  /// All poll addresses this device created (lowercased).
  Future<Set<String>> all();

  /// Record [pollAddress] as created by this device (idempotent).
  Future<void> add(String pollAddress);
}

/// Production store backed by `flutter_secure_storage` (a JSON address list).
class SecureCreatedPollsStore implements CreatedPollsStore {
  static const _key = 'tessera.created_polls';
  final FlutterSecureStorage _s;
  SecureCreatedPollsStore([FlutterSecureStorage? storage])
    : _s =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  @override
  Future<Set<String>> all() async {
    final raw = await _s.read(key: _key);
    if (raw == null || raw.isEmpty) return {};
    try {
      final list = jsonDecode(raw) as List;
      return list.map((e) => e.toString().toLowerCase()).toSet();
    } catch (_) {
      return {}; // corrupt value → treat as empty, never throw into the UI
    }
  }

  @override
  Future<void> add(String pollAddress) async {
    final set = await all()
      ..add(pollAddress.toLowerCase());
    await _s.write(key: _key, value: jsonEncode(set.toList()));
  }
}

/// In-memory store for tests and previews (no platform channels).
class InMemoryCreatedPollsStore implements CreatedPollsStore {
  final Set<String> _set;
  InMemoryCreatedPollsStore([Iterable<String>? initial])
    : _set = {...?initial?.map((e) => e.toLowerCase())};

  @override
  Future<Set<String>> all() async => {..._set};

  @override
  Future<void> add(String pollAddress) async =>
      _set.add(pollAddress.toLowerCase());
}
