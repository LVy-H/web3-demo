import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/crypto/org_keypair.dart';
import '../../../data/models/pending_voter.dart';
import '../../../data/repositories/live_host_repository.dart';
import '../../core/view_state.dart';

/// Organizer dashboard state: a per-poll org keypair, a rotating signed ticket
/// (the QR), a live pending-voter queue, confirm + phase actions. All timers are
/// cancelled on dispose.
class LiveHostViewModel extends ChangeNotifier {
  final LiveHostRepository _repo;
  final String pollAddress;
  LiveHostViewModel(this._repo, this.pollAddress);

  static const _rotateSeconds = 25;
  static const _rotate = Duration(seconds: _rotateSeconds);
  static const _pollEvery = Duration(seconds: 2);

  ViewState state = ViewState.idle;
  String? error;

  OrgKeypair? _kp;
  String? ticketUrl; // QR payload (URL containing a signed ticket)
  int _mintedAt = 0; // unix seconds
  int secondsLeft = _rotateSeconds;

  List<PendingVoter> queue = const [];
  bool busy = false;
  String? actionError;
  String? actionMsg;

  Timer? _rotateTimer, _pollTimer, _tickTimer;

  bool get canHost => _repo.canHost;
  String? get signer => _repo.signer;
  String? get orgPubKey => _kp?.pubKey;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    _cancelTimers();
    super.dispose();
  }

  void _cancelTimers() {
    _rotateTimer?.cancel();
    _pollTimer?.cancel();
    _tickTimer?.cancel();
    _rotateTimer = _pollTimer = _tickTimer = null;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

  Future<void> load() async {
    _cancelTimers(); // calling load() again must not stack timers
    state = ViewState.loading;
    error = null;
    _notify();
    try {
      _kp = await _repo.ensureOrgKeypair(pollAddress);
      if (_disposed) return; // navigated away during the async load
      _mint();
      await _refreshQueue();
      if (_disposed) return;
      state = ViewState.loaded;
      _rotateTimer = Timer.periodic(_rotate, (_) => _mint());
      _pollTimer = Timer.periodic(_pollEvery, (_) => _refreshQueue());
      _tickTimer =
          Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } catch (e) {
      error = e.toString();
      state = ViewState.error;
    }
    _notify();
  }

  void _mint() {
    final kp = _kp;
    if (kp == null) return;
    final now = _now;
    final wire = _repo.mintTicket(pollAddress, kp, now);
    // An app deep-link payload, not a hosted URL — we don't own a web domain
    // yet. The Tessera app scans this; LiveVoteViewModel.extractTicket still
    // pulls `?t=` from the custom scheme via Uri.queryParameters.
    ticketUrl = 'tessera://live/$pollAddress/vote?t=$wire';
    _mintedAt = now;
    secondsLeft = _rotateSeconds;
    _notify();
  }

  void _tick() {
    final left = _rotateSeconds - (_now - _mintedAt);
    secondsLeft = left < 0 ? 0 : left;
    _notify();
  }

  Future<void> _refreshQueue() async {
    try {
      queue = await _repo.queue(pollAddress);
      _notify();
    } catch (_) {
      // transient; keep the last queue
    }
  }

  Future<void> _run(Future<dynamic> Function() action, String okMsg) async {
    busy = true;
    actionError = null;
    actionMsg = null;
    _notify();
    try {
      await action();
      actionMsg = okMsg;
      await _refreshQueue();
    } catch (e) {
      actionError = e.toString();
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> confirm(PendingVoter v) =>
      _run(() => _repo.confirm(pollAddress, v), 'Confirmed ${v.confirmationCode}');
  Future<void> startVoting() =>
      _run(() => _repo.startVoting(pollAddress), 'Voting started');
  Future<void> endVoting() =>
      _run(() => _repo.endVoting(pollAddress), 'Voting ended');
}
