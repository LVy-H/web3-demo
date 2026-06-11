import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:core_chain/config.dart';

/// Persists the in-app network override (Settings → Network) so a hosted build
/// can be re-pointed at a custom backend without a rebuild. Read once at startup
/// (`main()`), written when the user saves, cleared on "reset to defaults".
///
/// Returns `null` when nothing is stored — the caller then keeps the
/// compile-time defaults. The store NEVER throws into startup: a corrupt blob
/// decodes to `null` (treated as "no override"). Format validity is the
/// caller's concern (`NetworkConfig.isValidFormat`) — the store only persists
/// and retrieves.
abstract class NetworkConfigStore {
  /// The saved override, or `null` if none is stored / the blob is unreadable.
  Future<NetworkConfig?> load();

  /// Persist [config] as the active override.
  Future<void> save(NetworkConfig config);

  /// Remove any override (revert to compile-time defaults on next load).
  Future<void> clear();
}

/// Production store backed by `flutter_secure_storage` (a single JSON blob).
/// Not secret, but it rides the same store as the identity seed and created-
/// polls record to avoid adding a prefs dependency.
class SecureNetworkConfigStore implements NetworkConfigStore {
  static const _key = 'tessera.network_config';
  final FlutterSecureStorage _s;
  SecureNetworkConfigStore([FlutterSecureStorage? storage])
    : _s =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  @override
  Future<NetworkConfig?> load() async {
    final raw = await _s.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return NetworkConfig.fromJson(map);
    } catch (_) {
      return null; // corrupt value → no override, never brick startup
    }
  }

  @override
  Future<void> save(NetworkConfig config) async =>
      _s.write(key: _key, value: jsonEncode(config.toJson()));

  @override
  Future<void> clear() async => _s.delete(key: _key);
}

/// In-memory store for tests and previews (no platform channels).
class InMemoryNetworkConfigStore implements NetworkConfigStore {
  NetworkConfig? _config;
  InMemoryNetworkConfigStore([this._config]);

  @override
  Future<NetworkConfig?> load() async => _config;

  @override
  Future<void> save(NetworkConfig config) async => _config = config;

  @override
  Future<void> clear() async => _config = null;
}
