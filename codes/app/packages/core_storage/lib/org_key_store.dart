import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Persists the per-poll organizer ed25519 keypair (as JSON). Abstracted so the
/// host flow is testable without the secure-storage platform channel.
abstract class OrgKeyStore {
  Future<String?> read(String pollId);
  Future<void> write(String pollId, String json);
}

class SecureOrgKeyStore implements OrgKeyStore {
  final FlutterSecureStorage _s;
  SecureOrgKeyStore([FlutterSecureStorage? storage])
    : _s =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  String _key(String poll) => 'tessera.orgkey.${poll.toLowerCase()}';

  @override
  Future<String?> read(String pollId) => _s.read(key: _key(pollId));
  @override
  Future<void> write(String pollId, String json) =>
      _s.write(key: _key(pollId), value: json);
}

class InMemoryOrgKeyStore implements OrgKeyStore {
  final _m = <String, String>{};
  @override
  Future<String?> read(String pollId) async => _m[pollId.toLowerCase()];
  @override
  Future<void> write(String pollId, String json) async =>
      _m[pollId.toLowerCase()] = json;
}
