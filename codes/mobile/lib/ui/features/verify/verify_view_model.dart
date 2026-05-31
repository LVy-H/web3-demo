import 'package:flutter/foundation.dart';

import '../../../data/repositories/verify_repository.dart';

enum VerifyVerdict { idle, checking, verified, notFound, error }

/// Verifies a vote receipt: does this nullifier appear as used in the poll?
/// Validates inputs locally before any chain call (mirrors the web Verify page).
class VerifyViewModel extends ChangeNotifier {
  final VerifyRepository _repo;
  VerifyViewModel(this._repo);

  static final _addr = RegExp(r'^0x[0-9a-fA-F]{40}$');
  static final _decimal = RegExp(r'^[0-9]+$');

  VerifyVerdict verdict = VerifyVerdict.idle;
  String? error;
  String? lastPoll;
  String? lastNullifier;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> verify(String pollAddress, String nullifier) async {
    final poll = pollAddress.trim();
    final nf = nullifier.trim();
    lastPoll = poll;
    lastNullifier = nf;
    if (!_addr.hasMatch(poll)) {
      error = 'Invalid poll address (expected 0x + 40 hex)';
      verdict = VerifyVerdict.error;
      _notify();
      return;
    }
    if (!_decimal.hasMatch(nf)) {
      error = 'Invalid nullifier (expected a decimal string)';
      verdict = VerifyVerdict.error;
      _notify();
      return;
    }
    verdict = VerifyVerdict.checking;
    error = null;
    _notify();
    try {
      final used = await _repo.isNullifierUsed(poll, nf);
      verdict = used ? VerifyVerdict.verified : VerifyVerdict.notFound;
    } catch (e) {
      error = e.toString();
      verdict = VerifyVerdict.error;
    }
    _notify();
  }
}
