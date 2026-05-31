import 'package:flutter/foundation.dart';

import '../../../data/models/poll_snapshot.dart';
import '../../../data/repositories/poll_repository.dart';
import '../../core/view_state.dart';

/// Loads a single poll's on-chain snapshot (phase, options, results, owner,
/// participant count) for the detail screen.
class PollDetailViewModel extends ChangeNotifier {
  final PollRepository _repo;
  final String address;
  PollDetailViewModel(this._repo, this.address);

  ViewState state = ViewState.idle;
  PollSnapshot? snapshot;
  String? error;

  Future<void> load() async {
    state = ViewState.loading;
    error = null;
    notifyListeners();
    try {
      snapshot = await _repo.fetchPoll(address);
      state = ViewState.loaded;
    } catch (e) {
      error = e.toString();
      state = ViewState.error;
    }
    notifyListeners();
  }
}
