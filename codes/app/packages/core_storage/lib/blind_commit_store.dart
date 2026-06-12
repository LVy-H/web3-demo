import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A blind vote a voter committed but hasn't revealed yet. The salt + option are
/// the only way to reveal later, so they're kept on-device (secure storage) per
/// poll until the reveal lands.
class SavedCommit {
  final int optionIndex;
  final String saltHex; // 0x + 64 hex
  const SavedCommit(this.optionIndex, this.saltHex);

  Map<String, dynamic> toJson() => {'o': optionIndex, 's': saltHex};
  factory SavedCommit.fromJson(Map<String, dynamic> j) =>
      SavedCommit(j['o'] as int, j['s'] as String);
}

abstract class BlindCommitStore {
  Future<void> save(String pollAddress, SavedCommit commit);
  Future<SavedCommit?> read(String pollAddress);
  Future<void> clear(String pollAddress);
}

class SecureBlindCommitStore implements BlindCommitStore {
  final FlutterSecureStorage _s;
  SecureBlindCommitStore([FlutterSecureStorage? storage])
    : _s =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  String _key(String poll) => 'tessera.blindcommit.${poll.toLowerCase()}';

  @override
  Future<void> save(String pollAddress, SavedCommit commit) =>
      _s.write(key: _key(pollAddress), value: jsonEncode(commit.toJson()));

  @override
  Future<SavedCommit?> read(String pollAddress) async {
    final raw = await _s.read(key: _key(pollAddress));
    if (raw == null) return null;
    return SavedCommit.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  @override
  Future<void> clear(String pollAddress) => _s.delete(key: _key(pollAddress));
}

class InMemoryBlindCommitStore implements BlindCommitStore {
  final _m = <String, SavedCommit>{};
  @override
  Future<void> save(String pollAddress, SavedCommit commit) async =>
      _m[pollAddress.toLowerCase()] = commit;
  @override
  Future<SavedCommit?> read(String pollAddress) async =>
      _m[pollAddress.toLowerCase()];
  @override
  Future<void> clear(String pollAddress) async =>
      _m.remove(pollAddress.toLowerCase());
}
