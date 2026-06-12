/// Production [OrganizerJourneyPort] / [OrganizerConsolePort] over the
/// sponsored relayer path + chain reads.
///
/// Deploy contract (PR #108): the poll is created through the relayer's
/// `create-poll` with the EXISTING pre-R4 `initialize` encodings from
/// `core_relay` (the relayer appends the trailing `resultsPolicy` argument
/// server-side — this class never re-encodes initialize). The spec §5
/// privacy choices travel as the optional top-level `visibility` /
/// `resultsPolicy` JSON fields via [OrganizeRelayGateway].
///
/// Phase actions prefer the sponsored route (the relayer OWNS sponsored
/// polls); the dev-signer [ChainWriter] is the fallback for dev-created
/// polls. Close has no sponsored route yet — without a dev signer it fails
/// with honest copy (a typed journey error state, never a dead end).
library;

import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/chain_writer.dart';
import 'package:core_chain/config.dart' show AppConfig;
import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_relay/poll_creator.dart' show SurveyQType, SurveyQuestion;
import 'package:core_relay/relay_client.dart';
import 'package:core_relay/sponsored_poll_creator.dart'
    show SponsoredPollCreator, encodeFlatInitData, encodeSurveyOuterInitData;
import 'package:core_storage/created_polls_store.dart';

import '../module_names.dart';
import 'organize_gateway.dart';
import 'organizer_console_port.dart';

class RelayOrganizerPort implements OrganizerConsolePort {
  final RelayClient relay;
  final ChainReader reader;
  final OrganizeRelayGateway gateway;
  final CreatedPollsStore createdPolls;

  /// Any flat `(address,address,string[])` module ABI — selector + encoding
  /// are identical across anon/approval/ranked/quadratic (see core_relay).
  final String flatModuleAbiJson;
  final String surveyVotingAbiJson;

  /// Dev-signer fallback for phase actions on dev-created polls; null in
  /// real builds.
  final ChainWriter? writer;

  /// ABI used for writer-path `startVoting`/`endVoting` (any module ABI —
  /// the phase functions share one signature across all six).
  final String? writerAbiJson;

  /// Clock seam for reveal-window checks.
  final int Function() nowSeconds;

  /// Module per poll address (lowercased), learned from deploys and
  /// dashboard loads, so module-aware reads need no extra chain round-trip.
  final Map<String, OrganizerModule> _modules = {};

  RelayOrganizerPort({
    required this.relay,
    required this.reader,
    required this.gateway,
    required this.createdPolls,
    required this.flatModuleAbiJson,
    required this.surveyVotingAbiJson,
    this.writer,
    this.writerAbiJson,
    int Function()? nowSeconds,
  }) : nowSeconds =
           nowSeconds ?? (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  static const _writerAbiName = 'ZkApprovalVoting';

  // ── OrganizerJourneyPort: deploy ──────────────────────────────────────────

  @override
  Future<String> deployPoll(OrganizerPollSpec spec) async {
    if (spec.module == OrganizerModule.blindVote) {
      // Honest limit: the relayer's sponsored allow-list excludes the
      // sealed-until-reveal module, and the lifted dev-signer creator
      // predates its R4 initialize shape. Surfaced as a typed deploy
      // failure with recovery, never attempted into a guaranteed revert.
      throw const OrganizeWireException(
        'Sealed-until-reveal polls can’t be created from this app yet — '
        'pick another poll type for now.',
      );
    }
    final info = await relay.getRelayerInfo();
    if (info == null) {
      throw const OrganizeWireException(
        'The sponsoring service is unreachable, so the poll can’t be '
        'created right now. Check the connection and try again.',
      );
    }
    final initData = spec.module == OrganizerModule.surveyVote
        ? encodeSurveyOuterInitData(
            surveyVotingAbiJson: surveyVotingAbiJson,
            semaphore: _semaphoreAddress,
            owner: info.relayer,
            questions: [
              // The on-chain question shape carries no prompt text and the
              // journey draft carries no per-question type; v1 deploys
              // single-choice questions (prompts stay app-side, as in the
              // legacy create flow).
              for (final q in spec.questions)
                SurveyQuestion(
                  qType: SurveyQType.singleChoice,
                  options: _trimmed(q.options),
                ),
            ],
          )
        : encodeFlatInitData(
            flatModuleAbiJson: flatModuleAbiJson,
            semaphore: _semaphoreAddress,
            owner: info.relayer,
            options: _trimmed(spec.options),
          );
    final result = await gateway.createPoll(
      moduleType: spec.module.wireName,
      title: spec.title.trim(),
      description: spec.description.trim(),
      initDataHex: SponsoredPollCreator.hexOf(initData),
      visibility: spec.visibility == PollVisibility.listed ? 1 : 0,
      resultsPolicy: spec.resultsPolicy == ResultsPolicy.livePublic ? 1 : 0,
    );
    final pollAddress = result.pollAddress;
    if (!result.ok || pollAddress == null) {
      throw OrganizeWireException(
        result.error ?? 'The poll could not be created. Try again.',
      );
    }
    _modules[pollAddress.toLowerCase()] = spec.module;
    try {
      await createdPolls.add(pollAddress);
    } catch (_) {
      // The poll exists on-chain; a failed local record must not turn a
      // successful create into an error. The address is still on screen.
    }
    return pollAddress;
  }

  /// The effective Semaphore address (overlaid once at startup by the app
  /// shell — see core_chain/config.dart). Read at deploy time, exactly like
  /// core_relay's own creators.
  String get _semaphoreAddress => AppConfig.semaphoreAddress;

  static List<String> _trimmed(List<String> raw) => [
    for (final option in raw)
      if (option.trim().isNotEmpty) option.trim(),
  ];

  // ── OrganizerJourneyPort: monitoring reads ────────────────────────────────

  @override
  Future<int> fetchRoster(String pollAddress) async =>
      (await reader.getParticipantCount(pollAddress)).toInt();

  @override
  Future<int> fetchTurnout(String pollAddress) async {
    final module = _modules[pollAddress.toLowerCase()];
    if (module == OrganizerModule.surveyVote) {
      final results = await reader.getSurveyResults(pollAddress);
      if (results.isEmpty) return 0;
      // Every respondent answers question 0, so its counts sum to ballots.
      return results.first.fold<BigInt>(BigInt.zero, (a, b) => a + b).toInt();
    }
    // Flat modules: the per-option counts sum to ballots for pick-one /
    // rank-them / sealed; for approve-any and split-points it counts marks
    // and points — the card labels it accordingly, never as people.
    final results = await reader.getResults(pollAddress);
    return results.fold<BigInt>(BigInt.zero, (a, b) => a + b).toInt();
  }

  @override
  Future<OrganizerResults> fetchResults(String pollAddress) async {
    final module = _modules[pollAddress.toLowerCase()];
    if (module == OrganizerModule.surveyVote) {
      final results = await reader.getSurveyResults(pollAddress);
      final tallies = <String, int>{};
      for (var q = 0; q < results.length; q++) {
        final options = await reader.getSurveyQuestionOptions(pollAddress, q);
        for (var i = 0; i < results[q].length; i++) {
          final label = i < options.length ? options[i] : 'option ${i + 1}';
          tallies['Q${q + 1}: $label'] = results[q][i].toInt();
        }
      }
      return OrganizerResults(tallies);
    }
    final options = await reader.getOptions(pollAddress);
    final counts = await reader.getResults(pollAddress);
    return OrganizerResults({
      for (var i = 0; i < counts.length; i++)
        (i < options.length ? options[i] : 'option ${i + 1}'): counts[i]
            .toInt(),
    });
  }

  // ── OrganizerJourneyPort: phase actions ───────────────────────────────────

  @override
  Future<void> startVoting(String pollAddress) async {
    try {
      await gateway.startVoting(pollAddress);
    } on Object {
      // Dev-created polls are owned by the dev signer, not the relayer;
      // fall through to the writer when one is configured.
      final w = writer;
      if (w == null || !w.canSign || writerAbiJson == null) rethrow;
      await w.send(
        to: pollAddress,
        abiJson: writerAbiJson!,
        abiName: _writerAbiName,
        function: 'startVoting',
      );
    }
  }

  @override
  Future<void> endVoting(String pollAddress) async {
    final w = writer;
    if (w != null && w.canSign && writerAbiJson != null) {
      await w.send(
        to: pollAddress,
        abiJson: writerAbiJson!,
        abiName: _writerAbiName,
        function: 'endVoting',
      );
      return;
    }
    // No dev signer: the sponsored close route (gateway surfaces honest
    // copy while the relayer doesn't expose one yet).
    await gateway.endVoting(pollAddress);
  }

  @override
  Future<void> finalize(String pollAddress) async {
    throw const OrganizeWireException(
      'Finalizing sealed-until-reveal results isn’t available from this '
      'app yet.',
    );
  }

  // ── OrganizerConsolePort: dashboard cold loads ────────────────────────────

  @override
  Future<List<RunPollSnapshot>> loadCreatedPolls() async {
    final mine = await createdPolls.all();
    if (mine.isEmpty) return const [];
    final infos = await reader.getAllPolls();
    final snapshots = <RunPollSnapshot>[];
    // Registry order is creation order; newest first on the dashboard.
    for (final info in infos.reversed) {
      if (!mine.contains(info.pollAddress.toLowerCase())) continue;
      final snapshot = await _snapshotFor(
        info.pollAddress,
        info.title,
        moduleForWireName(info.moduleType),
      );
      if (snapshot != null) snapshots.add(snapshot);
    }
    return snapshots;
  }

  @override
  Future<RunPollSnapshot?> loadPoll(String pollAddress) async {
    final infos = await reader.getAllPolls();
    for (final info in infos) {
      if (info.pollAddress.toLowerCase() == pollAddress.toLowerCase()) {
        return _snapshotFor(
          info.pollAddress,
          info.title,
          moduleForWireName(info.moduleType),
        );
      }
    }
    return null;
  }

  Future<RunPollSnapshot?> _snapshotFor(
    String pollAddress,
    String title,
    OrganizerModule? module,
  ) async {
    try {
      if (module != null) _modules[pollAddress.toLowerCase()] = module;
      final phase = await reader.getState(pollAddress);
      final roster = (await reader.getParticipantCount(pollAddress)).toInt();
      int? turnout;
      if (phase >= 1) {
        try {
          turnout = await fetchTurnout(pollAddress);
        } catch (_) {
          turnout = null; // tally read failed; the card shows roster only
        }
      }
      var finalized = false;
      var revealDeadline = 0;
      if (module == OrganizerModule.blindVote && phase >= 2) {
        finalized = await reader.isFinalized(pollAddress);
        revealDeadline = (await reader.getRevealDeadline(pollAddress)).toInt();
      }
      return RunPollSnapshot(
        pollAddress: pollAddress,
        title: title,
        module: module,
        phase: phase,
        roster: roster,
        turnout: turnout,
        finalized: finalized,
        revealDeadline: revealDeadline,
      );
    } catch (_) {
      return null; // unreadable poll: skip, never brick the dashboard
    }
  }
}
