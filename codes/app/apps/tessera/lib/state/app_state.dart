/// App-level state the router re-evaluates guards against (R2f deliverable 3).
///
/// Holds the [Capabilities] snapshot and identity presence; the journey
/// machines' active states join it in R3. Bound to go_router via
/// `refreshListenable`, so every change re-runs the redirect callbacks.
library;

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_storage/identity_store.dart';
import 'package:flutter/foundation.dart';

import '../capabilities/capability_prober.dart';

class AppState extends ChangeNotifier {
  final CapabilityProber _prober;
  final IdentityStore _identityStore;

  Capabilities _capabilities;
  bool _hasIdentity = false;
  bool _disposed = false;

  /// Constructed with the synchronous platform+config probe so guards that
  /// depend on `canProve` are correct before the first frame; [start]
  /// refines the async parts (relayer reachability, identity presence).
  AppState({
    required CapabilityProber prober,
    required IdentityStore identityStore,
  }) : _prober = prober,
       _identityStore = identityStore,
       _capabilities = prober.probePlatform();

  Capabilities get capabilities => _capabilities;

  /// Whether an identity seed exists on this device. A storage read failure
  /// counts as "no identity" — the lazy-creation flow (spec §3 principle 6)
  /// recovers from that honestly instead of crashing startup.
  bool get hasIdentity => _hasIdentity;

  /// Kick off the async probes. Fire-and-forget from the composition root;
  /// every completion notifies the router via [notifyListeners].
  Future<void> start() =>
      Future.wait([refreshCapabilities(), refreshIdentity()]);

  /// Re-probe hook for settings changes (network config edits, prover
  /// becoming available): runs the full capability probe and notifies.
  Future<void> refreshCapabilities() async {
    final next = await _prober.probe();
    if (_disposed || next == _capabilities) return;
    _capabilities = next;
    notifyListeners();
  }

  Future<void> refreshIdentity() async {
    bool present;
    try {
      final seed = await _identityStore.read();
      present = seed != null && seed.isNotEmpty;
    } catch (_) {
      present = false; // unreadable store == no usable identity
    }
    if (_disposed || present == _hasIdentity) return;
    _hasIdentity = present;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
