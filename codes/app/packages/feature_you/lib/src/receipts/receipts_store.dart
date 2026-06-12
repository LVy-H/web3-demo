// The receipts archive store. The interface lives HERE (feature_you owns the
// receipts surface in R3); when feature_vote's after-cast journey starts
// persisting receipts, the interface graduates to core_storage in the R3
// integration pass and this file re-exports it.
//
// flutter_secure_storage is resolved through the pub workspace (it is a
// direct dependency of core_storage, which this package depends on); the
// pubspec declaration moves together with the store's graduation to
// core_storage — pubspecs are frozen during the R3 fan-out.
// ignore_for_file: depend_on_referenced_packages
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'vote_receipt.dart';

/// Persists the voter's saved receipts (newest first). Receipts are not
/// secrets in the identity-seed sense, but they link this DEVICE to specific
/// polls, so they ride the same secure store as everything else in
/// core_storage rather than plaintext prefs.
abstract class ReceiptsStore {
  /// All saved receipts, newest first. Never throws into the UI — an
  /// unreadable store is an empty archive.
  Future<List<VoteReceipt>> loadAll();

  /// Save (or update) a receipt. Upserts on (pollAddress, receiptCode) so a
  /// re-save after re-verifying never duplicates an entry.
  Future<void> save(VoteReceipt receipt);

  /// Remove one receipt.
  Future<void> remove(String pollAddress, String receiptCode);

  /// Drop the whole archive.
  Future<void> clear();
}

bool _sameReceipt(VoteReceipt r, String pollAddress, String receiptCode) =>
    r.pollAddress.toLowerCase() == pollAddress.toLowerCase() &&
    r.receiptCode == receiptCode;

/// Production store backed by `flutter_secure_storage` (a single JSON blob,
/// following the core_storage pattern — see `blind_commit_store.dart`).
class SecureReceiptsStore implements ReceiptsStore {
  static const _key = 'tessera.receipts';
  final FlutterSecureStorage _s;
  SecureReceiptsStore([FlutterSecureStorage? storage])
    : _s =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(encryptedSharedPreferences: true),
          );

  @override
  Future<List<VoteReceipt>> loadAll() async {
    try {
      return VoteReceipt.decodeList(await _s.read(key: _key));
    } catch (_) {
      return const []; // unreadable store == empty archive, never a crash
    }
  }

  @override
  Future<void> save(VoteReceipt receipt) async {
    final all = await loadAll();
    all.removeWhere(
      (r) => _sameReceipt(r, receipt.pollAddress, receipt.receiptCode),
    );
    all.insert(0, receipt);
    await _s.write(key: _key, value: VoteReceipt.encodeList(all));
  }

  @override
  Future<void> remove(String pollAddress, String receiptCode) async {
    final all = await loadAll();
    all.removeWhere((r) => _sameReceipt(r, pollAddress, receiptCode));
    await _s.write(key: _key, value: VoteReceipt.encodeList(all));
  }

  @override
  Future<void> clear() => _s.delete(key: _key);
}

/// In-memory store for tests and previews (no platform channels).
class InMemoryReceiptsStore implements ReceiptsStore {
  final List<VoteReceipt> _receipts;
  InMemoryReceiptsStore([List<VoteReceipt>? seed])
    : _receipts = List.of(seed ?? const []);

  @override
  Future<List<VoteReceipt>> loadAll() async => List.unmodifiable(_receipts);

  @override
  Future<void> save(VoteReceipt receipt) async {
    _receipts.removeWhere(
      (r) => _sameReceipt(r, receipt.pollAddress, receipt.receiptCode),
    );
    _receipts.insert(0, receipt);
  }

  @override
  Future<void> remove(String pollAddress, String receiptCode) async =>
      _receipts.removeWhere((r) => _sameReceipt(r, pollAddress, receiptCode));

  @override
  Future<void> clear() async => _receipts.clear();
}
