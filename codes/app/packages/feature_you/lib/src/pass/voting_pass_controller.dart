import 'package:core_storage/identity_store.dart';
import 'package:flutter/foundation.dart';

/// Awaited after every successful pass change so the app shell can refresh
/// its identity-presence state (R2f's `AppState.refreshIdentity`, which the
/// router guards re-evaluate against via `refreshListenable`).
typedef PassChanged = Future<void> Function();

/// Derives the registration code (the Semaphore identity commitment — never
/// called that in UI copy) for a seed. `null` when no prover is available on
/// this platform: the advanced panel then shows honest unavailable copy.
typedef RegistrationCodeDeriver = Future<String> Function(String seed);

/// State for the voting pass surface (spec §3 principles 5–6: the identity
/// seed without the identity jargon). Wraps core_storage's [IdentityStore]:
/// load / create / import / remove, plus lazy registration-code derivation.
///
/// Every store write is try/caught into [error] with the busy flag reset —
/// a failing secure store can never leave the UI stuck on "SAVING…" (the
/// historical save-hang class).
class VotingPassController extends ChangeNotifier {
  final IdentityStore _store;
  final PassChanged _onPassChanged;
  final RegistrationCodeDeriver? _deriveRegistrationCode;
  final String Function() _generateSeed;

  VotingPassController({
    required IdentityStore store,
    required PassChanged onPassChanged,
    RegistrationCodeDeriver? deriveRegistrationCode,
    String Function()? generateSeed,
  }) : _store = store,
       _onPassChanged = onPassChanged,
       _deriveRegistrationCode = deriveRegistrationCode,
       _generateSeed = generateSeed ?? generateIdentitySeed;

  bool loading = true;
  bool busy = false;
  String? error;

  String? _seed;

  /// The pass secret. Only the backup panel ever renders it.
  String? get seed => _seed;
  bool get hasPass => _seed != null && _seed!.isNotEmpty;

  /// Whether this platform can derive a registration code at all.
  bool get canDeriveRegistrationCode => _deriveRegistrationCode != null;
  String? registrationCode;
  bool derivingCode = false;
  String? _codeSeed; // the seed [registrationCode] belongs to

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
      // Unreadable store == no usable pass (mirrors AppState.refreshIdentity).
      _seed = null;
      error = 'Could not read this device’s secure storage: $e';
    }
    loading = false;
    _notify();
  }

  /// Create a fresh pass. Returns true on success.
  Future<bool> create() => _save(_generateSeed());

  /// Import a pass the user pasted. Returns false (with [error]) on blank
  /// input or a failed write.
  Future<bool> importPass(String raw) async {
    final s = raw.trim();
    if (s.isEmpty) {
      error = 'Paste your pass first.';
      _notify();
      return false;
    }
    return _save(s);
  }

  /// Remove the pass from this device. Returns true on success.
  Future<bool> remove() async {
    busy = true;
    error = null;
    _notify();
    var ok = false;
    try {
      await _store.delete();
      _seed = null;
      registrationCode = null;
      _codeSeed = null;
      await _onPassChanged();
      ok = true;
    } catch (e) {
      error = 'Could not remove the pass: $e';
    }
    busy = false;
    _notify();
    return ok;
  }

  Future<bool> _save(String seed) async {
    busy = true;
    error = null;
    _notify();
    var ok = false;
    try {
      await _store.write(seed);
      _seed = seed;
      registrationCode = null;
      _codeSeed = null;
      await _onPassChanged();
      ok = true;
    } catch (e) {
      error = 'Could not save the pass: $e';
    }
    busy = false;
    _notify();
    return ok;
  }

  /// Derive the registration code for the current pass, once per seed.
  /// No-op when no deriver is available or a derivation is in flight; a
  /// failed derivation leaves [registrationCode] null (the panel shows the
  /// honest unavailable copy) instead of throwing.
  Future<void> ensureRegistrationCode() async {
    final derive = _deriveRegistrationCode;
    final s = _seed;
    if (derive == null || s == null || s.isEmpty) return;
    if (derivingCode || _codeSeed == s) return;
    derivingCode = true;
    _notify();
    try {
      final code = await derive(s);
      if (_seed == s) {
        registrationCode = code;
        _codeSeed = s;
      }
    } catch (_) {
      // Leave null — rendered as "not available on this device".
    }
    derivingCode = false;
    _notify();
  }
}
