import 'package:flutter/foundation.dart';

import '../../../data/models/blind_snapshot.dart';
import '../../../data/repositories/blind_repository.dart';
import '../../core/view_state.dart';

/// Drives the M2 blind-poll screen: loads the snapshot + this signer's status,
/// and runs the lifecycle actions (register / commit / reveal and the owner's
/// start / end / finalize), refreshing after each without a full reload flicker.
class BlindPollViewModel extends ChangeNotifier {
  final BlindRepository _repo;
  final String pollAddress;
  BlindPollViewModel(this._repo, this.pollAddress);

  ViewState state = ViewState.idle;
  BlindSnapshot? snapshot;
  String? error;

  bool busy = false;
  String? actionError;
  String? actionMsg;
  bool hasSavedCommit = false;

  bool get canWrite => _repo.canWrite;
  String? get signer => _repo.signer;

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
    state = ViewState.loading;
    error = null;
    _notify();
    try {
      await _refresh();
      state = ViewState.loaded;
    } catch (e) {
      error = e.toString();
      state = ViewState.error;
    }
    _notify();
  }

  Future<void> _refresh() async {
    snapshot = await _repo.fetch(pollAddress);
    hasSavedCommit = await _repo.hasSavedCommit(pollAddress);
  }

  Future<void> _run(Future<String> Function() action, String okMsg) async {
    busy = true;
    actionError = null;
    actionMsg = null;
    _notify();
    try {
      await action();
      actionMsg = okMsg;
      await _refresh();
    } catch (e) {
      actionError = e.toString();
    } finally {
      busy = false;
      _notify();
    }
  }

  // Voter
  Future<void> register() => _run(() => _repo.register(pollAddress), 'Registered');
  Future<void> commit(int option) =>
      _run(() => _repo.commit(pollAddress, option), 'Vote committed');
  Future<void> reveal() => _run(() => _repo.reveal(pollAddress), 'Vote revealed');

  // Owner
  Future<void> startVoting() =>
      _run(() => _repo.startVoting(pollAddress), 'Voting started');
  Future<void> endVoting() =>
      _run(() => _repo.endVoting(pollAddress), 'Voting ended');
  Future<void> finalize() =>
      _run(() => _repo.finalize(pollAddress), 'Results finalized');
}
