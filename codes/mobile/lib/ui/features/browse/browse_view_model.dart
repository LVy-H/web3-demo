import 'package:flutter/foundation.dart';

import '../../../data/models/poll_info.dart';
import '../../../data/repositories/poll_repository.dart';
import '../../core/view_state.dart';

/// Loads the list of polls for the Browse screen. Exposes an immutable snapshot
/// (state + polls + error); the View only reads and triggers [load].
class BrowseViewModel extends ChangeNotifier {
  final PollRepository _repo;
  BrowseViewModel(this._repo);

  ViewState state = ViewState.idle;
  List<PollInfo> polls = const [];
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
    state = ViewState.loading;
    error = null;
    _notify();
    try {
      polls = await _repo.fetchPolls();
      state = ViewState.loaded;
    } catch (e) {
      error = e.toString();
      state = ViewState.error;
    }
    _notify();
  }
}
