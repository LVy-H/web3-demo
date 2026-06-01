import 'package:flutter/foundation.dart';

import '../../../data/models/poll_info.dart';
import '../../../data/models/poll_summary.dart';
import '../../../data/repositories/poll_repository.dart';
import '../../core/view_state.dart';

/// Loads the list of polls for the Browse screen. Exposes an immutable snapshot
/// (state + polls + per-poll summaries + error); the View only reads and
/// triggers [load].
class BrowseViewModel extends ChangeNotifier {
  final PollRepository _repo;
  BrowseViewModel(this._repo);

  ViewState state = ViewState.idle;
  List<PollInfo> polls = const [];

  /// Per-poll lifecycle state + vote tally, keyed by poll address. Populated
  /// best-effort: a poll whose summary read fails is simply absent here (the
  /// card falls back to a neutral look) rather than failing the whole list.
  Map<String, PollSummary> summaries = const {};
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
    summaries = const {};
    _notify();
    try {
      polls = await _repo.fetchPolls();
      summaries = await _loadSummaries(polls);
      state = ViewState.loaded;
    } catch (e) {
      error = e.toString();
      state = ViewState.error;
    }
    _notify();
  }

  /// Fetch each poll's summary concurrently, best-effort. A failed read drops
  /// that poll from the map; it never throws (so it can't flip us to error).
  Future<Map<String, PollSummary>> _loadSummaries(List<PollInfo> ps) async {
    final out = <String, PollSummary>{};
    await Future.wait(ps.map((p) async {
      try {
        out[p.pollAddress] = await _repo.fetchSummary(p.pollAddress);
      } catch (_) {
        // leave absent — card falls back to a neutral look
      }
    }));
    return out;
  }
}
