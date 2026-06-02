import 'package:flutter/foundation.dart';

import '../../../data/services/identity_store.dart';

/// Manages the single app identity seed: load it from the secure store, create a
/// fresh one, import an existing seed (e.g. an organizer invite token), or clear
/// it. The seed is the only secret a recurring member needs to cast votes.
class IdentityViewModel extends ChangeNotifier {
  final IdentityStore _store;
  IdentityViewModel(this._store);

  String? _seed;
  String? get seed => _seed;
  bool get hasIdentity => _seed != null && _seed!.isNotEmpty;

  bool loading = true;
  String? error;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    loading = true;
    error = null;
    _notify();
    try {
      _seed = await _store.read();
    } catch (e) {
      error = 'Secure storage unavailable: $e';
    }
    loading = false;
    _notify();
  }

  Future<void> createNew() => _save(generateIdentitySeed());

  /// Imports a pasted seed / invite token. Returns false (with [error] set) when
  /// the input is blank.
  Future<bool> import(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) {
      error = 'Paste a seed or invite token first.';
      _notify();
      return false;
    }
    await _save(s);
    return true;
  }

  Future<void> clear() async {
    error = null;
    try {
      await _store.delete();
      _seed = null;
    } catch (e) {
      error = 'Could not clear identity: $e';
    }
    _notify();
  }

  Future<void> _save(String seed) async {
    error = null;
    try {
      await _store.write(seed);
      _seed = seed;
    } catch (e) {
      error = 'Could not save identity: $e';
    }
    _notify();
  }
}
