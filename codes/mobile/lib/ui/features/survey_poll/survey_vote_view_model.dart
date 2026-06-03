import 'package:flutter/foundation.dart';

import '../../../core/crypto/survey_commit.dart';
import '../../../data/repositories/survey_repository.dart';
import '../../../data/services/proof_service.dart';
import '../../../data/services/relay_client.dart';
import '../../core/view_state.dart';

enum SurveyVoteStatus { idle, proving, relaying, success, error }

/// Drives the Phase 12d survey detail surface (module `survey-vote`): loads the
/// multi-question survey structure + per-question results + registration, holds
/// the per-question answer state, builds the single answer VECTOR, and casts ONE
/// anonymous ballot binding the WHOLE vector into the proof.
///
/// Sibling of [QuadraticVoteViewModel] with the survey twist: the ballot is a
/// `List<BigInt> answers` (one word per question) — NOT a single packed int —
/// and the Semaphore `message` is the WIDE keccak commitment
/// `surveyCommitment(answers)` (`keccak256(abi.encode(answers)) >> 8`), proven
/// via [ProofService.generateVoteProofWide]. The contract recomputes that
/// commitment from the relayed `answers` and reverts (`TamperedVoteSignal`)
/// unless `proof.message == surveyCommitment(answers)` — so the answers we
/// COMMIT, PROVE, and RELAY must be the SAME vector: [buildAnswers] computes it
/// once in [castSurvey].
///
/// Per-question answer state:
///   - SingleChoice: a single chosen option index (`-1` = none yet) in
///     [singleSelections].
///   - MultiSelect: a set of checked option indices in [multiSelections].
class SurveyVoteViewModel extends ChangeNotifier {
  final SurveyRepository _repo;
  final ProofService _proofService;
  final RelayClient _relay;
  final String pollAddress;

  SurveyVoteViewModel({
    required SurveyRepository repository,
    required ProofService proofService,
    required RelayClient relayClient,
    required this.pollAddress,
  })  : _repo = repository,
        _proofService = proofService,
        _relay = relayClient;

  // ── Survey load ─────────────────────────────────────────────────────────────
  ViewState state = ViewState.idle;
  String? error;
  SurveyStructure? survey;

  /// One chosen option index per SingleChoice question (`-1` = no selection
  /// yet). Indexed by question. MultiSelect questions hold `-1` here (unused).
  List<int> singleSelections = <int>[];

  /// One set of checked option indices per MultiSelect question. Indexed by
  /// question. SingleChoice questions hold an empty set here (unused).
  List<Set<int>> multiSelections = <Set<int>>[];

  int get questionCount => survey?.questionCount ?? 0;

  Future<void> load() async {
    state = ViewState.loading;
    _notify();
    try {
      final s = await _repo.fetchSurvey(pollAddress);
      survey = s;
      // Size the answer state to the questions: one slot per question.
      singleSelections = List<int>.filled(s.questionCount, -1);
      multiSelections = [for (var q = 0; q < s.questionCount; q++) <int>{}];
      state = ViewState.loaded;
    } catch (e) {
      error = e.toString();
      state = ViewState.error;
    }
    _notify();
  }

  // ── Answer form state ────────────────────────────────────────────────────────

  /// Select option [optionIndex] for SingleChoice question [q] (radio behavior).
  void selectSingle(int q, int optionIndex) {
    if (isBusy || q < 0 || q >= singleSelections.length) return;
    singleSelections[q] = optionIndex;
    _notify();
  }

  /// Toggle option [optionIndex] for MultiSelect question [q] (checkbox).
  void toggleMulti(int q, int optionIndex) {
    if (isBusy || q < 0 || q >= multiSelections.length) return;
    final set = multiSelections[q];
    if (!set.add(optionIndex)) set.remove(optionIndex);
    _notify();
  }

  /// Whether question [q] currently has a valid answer: SingleChoice needs a
  /// selection; MultiSelect needs ≥1 box checked (mirrors the contract's
  /// all-mandatory + non-empty-multiselect rule).
  bool isAnswered(int q) {
    final s = survey;
    if (s == null || q < 0 || q >= s.questions.length) return false;
    if (s.questions[q].isMultiSelect) {
      return multiSelections[q].isNotEmpty;
    }
    return singleSelections[q] >= 0;
  }

  /// Build the answer VECTOR (`List<BigInt>`, one word per question, in question
  /// order). SingleChoice ⇒ `BigInt.from(selectedIndex)`; MultiSelect ⇒ the
  /// BigInt bitmask (`m |= BigInt.one << i` for each checked option i — built
  /// with [BigInt] NOT `1 << i`, which the dart2js 32-bit shift bug corrupts at
  /// option ≥ 31). Throws [StateError] if any question is unanswered (the cast
  /// path calls [canCast] first, so this is the defensive guard).
  List<BigInt> buildAnswers() {
    final s = survey;
    if (s == null) throw StateError('survey not loaded');
    final answers = <BigInt>[];
    for (var q = 0; q < s.questions.length; q++) {
      final question = s.questions[q];
      if (question.isMultiSelect) {
        final selected = multiSelections[q];
        if (selected.isEmpty) {
          throw StateError('question $q (multi-select) has no selection');
        }
        // Build the bitmask with BigInt — bit i set ⇒ option i chosen. Option
        // indices can reach 31 (MAX_OPTIONS = 32), so `1 << i` (a 32-bit dart2js
        // int shift) would corrupt the high bit; BigInt is mandatory.
        var m = BigInt.zero;
        for (final i in selected) {
          m |= BigInt.one << i;
        }
        answers.add(m);
      } else {
        final idx = singleSelections[q];
        if (idx < 0) {
          throw StateError('question $q (single-choice) has no selection');
        }
        answers.add(BigInt.from(idx));
      }
    }
    return answers;
  }

  /// Whether EVERY question is answered (SingleChoice has a selection,
  /// MultiSelect has ≥1 box) and the survey is loaded — the cast-button gate.
  /// Mirrors the contract's all-mandatory + non-empty-multiselect rule and its
  /// `answers.length == questions.length` check.
  bool get allAnswered {
    final s = survey;
    if (s == null || s.questions.isEmpty) return false;
    for (var q = 0; q < s.questions.length; q++) {
      if (!isAnswered(q)) return false;
    }
    return true;
  }

  /// Whether a cast is allowed: every question answered (the contract's
  /// mandatory rule), an identity entered (checked at cast), and no cast in
  /// flight.
  bool get canCast => allAnswered && !isBusy;

  // ── Cast ─────────────────────────────────────────────────────────────────────
  SurveyVoteStatus status = SurveyVoteStatus.idle;
  String? castError;
  String? txHash;

  bool get isBusy =>
      status == SurveyVoteStatus.proving ||
      status == SurveyVoteStatus.relaying;

  // Proactive registration status for the entered identity (same pattern as the
  // sibling modules) — the voter sees they aren't a member BEFORE casting.
  String? myCommitment;
  bool? isRegistered; // null = unknown / check failed
  bool checkingRegistration = false;

  // Monotonic token: a late result from a superseded checkRegistration() call
  // (re-typed seed, or cleared field) is dropped so it can't overwrite newer
  // state.
  int _regToken = 0;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  // castSurvey is long-running (proving + relaying); guard against notifying
  // after the screen popped and disposed this notifier.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Derive the entered identity's commitment and check whether it's already a
  /// member of this survey's group, so the form can show registration status
  /// up-front. Failures leave [isRegistered] null (unknown) rather than error.
  Future<void> checkRegistration(String identitySeed) async {
    checkingRegistration = true;
    _notify();
    final token = ++_regToken;
    try {
      final commitment = await _proofService.deriveCommitment(identitySeed);
      final group = await _repo.fetchGroup(pollAddress);
      if (token != _regToken) return;
      myCommitment = commitment;
      isRegistered = group.contains(commitment);
    } catch (_) {
      if (token == _regToken) isRegistered = null;
    } finally {
      if (token == _regToken) {
        checkingRegistration = false;
        _notify();
      }
    }
  }

  /// Clear any registration status (e.g. the seed field was emptied) and
  /// supersede any in-flight [checkRegistration].
  void clearRegistration() {
    _regToken++;
    myCommitment = null;
    isRegistered = null;
    checkingRegistration = false;
    _notify();
  }

  /// Cast the current survey ballot. Builds the answer vector ONCE, binds it
  /// into the proof via the wide keccak commitment, and relays the SAME vector —
  /// the contract recomputes the commitment from the relayed answers and reverts
  /// unless they match.
  Future<void> castSurvey({required String identitySeed}) async {
    castError = null;
    txHash = null;
    if (!allAnswered) {
      // Mirror the contract's all-mandatory rule — never relay a partial ballot.
      castError = 'Answer every question before casting.';
      status = SurveyVoteStatus.error;
      _notify();
      return;
    }

    // ── Compute the answer vector ONCE. The SAME `answers` is committed, proven,
    // and relayed; the contract recomputes `keccak256(abi.encode(answers)) >> 8`
    // and reverts (TamperedVoteSignal) unless `proof.message == that`. Binding
    // one vector and relaying another would brick every cast. ───────────────────
    final List<BigInt> answers;
    try {
      answers = buildAnswers();
    } catch (e) {
      castError = e.toString();
      status = SurveyVoteStatus.error;
      _notify();
      return;
    }
    final message = surveyCommitment(answers);

    status = SurveyVoteStatus.proving;
    _notify();
    try {
      final group = await _repo.fetchGroup(pollAddress);
      // Membership pre-check: proving over a group you're not a member of fails
      // deep in Semaphore with a cryptic "leaf at index -1". Surface a clear
      // message instead (you can only vote anonymously once registered).
      final commitment = await _proofService.deriveCommitment(identitySeed);
      if (!group.contains(commitment)) {
        castError =
            "This identity isn't registered in this survey yet. Ask the "
            "organizer to confirm you (scan the live-meeting QR), or have your "
            "commitment registered first.";
        status = SurveyVoteStatus.error;
        _notify();
        return;
      }
      // The wide keccak commitment is the proof's `message`. The relayer's
      // message check is shape-only; the CONTRACT recomputes the commitment from
      // the relayed `answers` and binds it — so no one can re-weight a single
      // answer without invalidating the SNARK.
      final proof = await _proofService.generateVoteProofWide(
        identitySeed: identitySeed,
        memberCommitments: group,
        message: message.toString(),
        scope: pollAddress,
      );
      status = SurveyVoteStatus.relaying;
      _notify();
      // Relay the SAME `answers` vector that was committed + proven.
      final result = await _relay.relaySurveyVote(pollAddress, answers, proof);
      if (result.success) {
        txHash = result.txHash;
        status = SurveyVoteStatus.success;
      } else {
        castError = result.error ?? 'Relay failed';
        status = SurveyVoteStatus.error;
      }
    } catch (e) {
      castError = e.toString();
      status = SurveyVoteStatus.error;
    }
    _notify();
  }
}
