/// Server-backed [OrganizerConsolePort] over the Phase-2 REST API
/// (`codes/server`) — the OPEN-BALLOT organizer path. Mirrors
/// [RelayOrganizerPort] but talks to the self-hosted bulletin-board server
/// (Decisions + Ballots) instead of the chain/relayer.
///
/// Vocabulary bridge: the journey speaks "poll address / module / phase 0-1-2";
/// the server speaks "decision id / method / state string". This adapter is
/// the ONLY place that translation lives:
///
///   - `pollAddress` (journey) == decision `id` (server). The server returns an
///     opaque `id` from `POST /decisions`; we thread it everywhere a poll
///     address is expected.
///   - module → method: anon→'single', approval→'approval', ranked→'ranked',
///     quadratic→'quadratic', survey→'survey'. Blind is Phase 3 (rejected).
///   - state string → phase int: draft→0, open→1, closed/challenge/published→2.
///
/// Lifecycle mapping: deployPoll→POST /decisions; startVoting→/open;
/// endVoting→/close; finalize→Phase-3 error; fetchResults→/results;
/// fetchTurnout→/turnout; fetchRoster→turnout (open mode has no separate
/// roster — every cast is a participant). loadCreatedPolls reads ids from
/// [CreatedPollsStore] then GETs each public decision view (404s skipped).
///
/// Convener routes need the Bearer token (server admin token); the injected
/// [ServerClient] carries it. Publish is exposed via [publishDecision] for the
/// console's publish step, layered on the journey's close→publish flow.
library;

import 'package:core_chain/config.dart' show AppConfig;
import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:core_domain/journeys/policy.dart';
import 'package:core_relay/server_client.dart';
import 'package:core_storage/created_polls_store.dart';

import 'organize_gateway.dart' show OrganizeWireException;
import 'organizer_console_port.dart';

/// The server `method` string for a journey [OrganizerModule].
/// Open-ballot only: `blindVote` has no server method (Phase 3).
String? serverMethodFor(OrganizerModule module) => switch (module) {
  OrganizerModule.anonVote => 'single',
  OrganizerModule.approvalVote => 'approval',
  OrganizerModule.rankedVote => 'ranked',
  OrganizerModule.quadraticVote => 'quadratic',
  OrganizerModule.surveyVote => 'survey',
  OrganizerModule.blindVote => null,
};

/// The journey [OrganizerModule] for a server `method` string (reverse of
/// [serverMethodFor]); null for an unknown method.
OrganizerModule? moduleForServerMethod(String method) => switch (method) {
  'single' => OrganizerModule.anonVote,
  'approval' => OrganizerModule.approvalVote,
  'ranked' => OrganizerModule.rankedVote,
  'quadratic' => OrganizerModule.quadraticVote,
  'survey' => OrganizerModule.surveyVote,
  _ => null,
};

/// Server decision `state` string → journey phase int (0=registration/pre,
/// 1=voting, 2=ended). draft→0; open→1; everything terminal (closed,
/// challenge, published, cancelled)→2.
int phaseForState(String state) => switch (state) {
  'draft' => 0,
  'open' => 1,
  _ => 2, // closed | challenge | published | cancelled
};

class ServerOrganizerPortAdapter implements OrganizerConsolePort {
  final ServerClient client;
  final CreatedPollsStore createdPolls;

  /// Per-decision option labels, learned from create + public reads, so
  /// `fetchResults` can label `/results` `optionScores` (which carry indices,
  /// not labels). Keyed by decision id.
  final Map<String, List<String>> _options = {};

  ServerOrganizerPortAdapter({
    required this.client,
    required this.createdPolls,
  });

  // ── OrganizerJourneyPort: deploy ──────────────────────────────────────────

  @override
  Future<String> deployPoll(OrganizerPollSpec spec) async {
    final method = serverMethodFor(spec.module);
    if (method == null) {
      // Sealed-until-reveal is a Phase-3 (secret-ballot) capability; the
      // open-ballot server has no method for it. Honest, recoverable failure.
      throw const OrganizeWireException(
        'Sealed-until-reveal polls aren’t available on the open-ballot '
        'server yet — pick another poll type for now.',
      );
    }
    // Survey questions aren't a flat option list; the open-ballot server's
    // survey method tallies a single multi-select option set, so v1 deploys
    // the first question's options (prompts stay app-side, as elsewhere).
    final options = method == 'survey'
        ? _trimmed(
            spec.questions.isNotEmpty
                ? spec.questions.first.options
                : const <String>[],
          )
        : _trimmed(spec.options);

    final body = <String, dynamic>{
      'title': spec.title.trim(),
      'options': options,
      'method': method,
      // Open-ballot is THE Phase-4 path: ballotMode 'open', not 'secret'.
      'ballotMode': 'open',
      // Journey ResultsPolicy → server enum: livePublic→'live', else 'sealed'.
      'resultsPolicy': spec.resultsPolicy == ResultsPolicy.livePublic
          ? 'live'
          : 'sealed',
      // Open eligibility: anyone with the link can cast (no gate at cast time).
      'eligibility': const {'method': 'open'},
      // Plurality + declare is the neutral default the journey doesn't model
      // yet (the create draft has no rule field); the convener can amend later.
      'rule': const {
        'threshold': {'kind': 'plurality'},
        'tieBreak': 'declare',
      },
      'schedule': const <String, dynamic>{},
      // Spec §5 default: link-only (unlisted) unless explicitly listed.
      'visibility': spec.visibility == PollVisibility.listed
          ? 'listed'
          : 'link-only',
      // Phase-2 has no on-chain anchor; 'casual' is the no-broadcast mode.
      'anchorMode': 'casual',
    };

    final Map<String, dynamic> created;
    try {
      created = await client.createDecision(body);
    } on ServerException catch (e) {
      throw OrganizeWireException(_deployCopy(e));
    }
    final id = created['id'];
    if (id is! String || id.isEmpty) {
      throw const OrganizeWireException(
        'The poll could not be created. Try again.',
      );
    }
    _options[id] = options;

    // Open the decision immediately so the create flow lands on a live poll
    // (the open-ballot demo has no separate "registration" phase — a created
    // decision is 'draft' until opened, and voters can only cast once open).
    try {
      await client.openDecision(id);
    } on ServerException {
      // Created but not yet open: the dashboard will show it draft and the
      // organizer's START VOTING re-attempts /open. Never fail the create.
    }

    try {
      await createdPolls.add(id);
    } catch (_) {
      // Local record only — a failed write must not turn a successful create
      // into an error (the id is already on screen).
    }
    return id;
  }

  String _deployCopy(ServerException e) {
    if (e.code == 'FORBIDDEN' || e.status == 401 || e.status == 403) {
      return 'This device isn’t signed in as the convener. Paste the admin '
          'token from the server (Settings → Network) and try again.';
    }
    if (e.code == 'VALIDATION') {
      return 'The poll details were rejected by the server. Check the title '
          'and options.';
    }
    return e.message;
  }

  static List<String> _trimmed(List<String> raw) => [
    for (final option in raw)
      if (option.trim().isNotEmpty) option.trim(),
  ];

  // ── OrganizerJourneyPort: monitoring reads ────────────────────────────────

  @override
  Future<int> fetchRoster(String pollAddress) async {
    // Open mode has no separate roster: anyone with the link can cast, and
    // turnout (the cast count) is the only participant signal. The convener
    // turnout route needs the token; fall back to the public view's turnout.
    try {
      final t = await client.getTurnout(pollAddress);
      return _asInt(t['count']);
    } on ServerException {
      final d = await client.getDecision(pollAddress);
      return _asInt(d['turnout']);
    }
  }

  @override
  Future<int> fetchTurnout(String pollAddress) async {
    try {
      final t = await client.getTurnout(pollAddress);
      return _asInt(t['count']);
    } on ServerException {
      // No convener token (or not the convener): the public view also carries
      // turnout, which is what the dashboard shows.
      final d = await client.getDecision(pollAddress);
      return _asInt(d['turnout']);
    }
  }

  @override
  Future<OrganizerResults> fetchResults(String pollAddress) async {
    final res = await client.getResults(pollAddress);
    final tally = res['tally'];
    final scores = tally is Map ? tally['optionScores'] : null;
    final labels = await _optionsFor(pollAddress);
    final tallies = <String, int>{};
    if (scores is List) {
      for (var i = 0; i < scores.length; i++) {
        final label = i < labels.length ? labels[i] : 'option ${i + 1}';
        tallies[label] = _asInt(scores[i]);
      }
    }
    // Surface abstain as its own bucket so it isn't silently dropped (the
    // server counts it toward turnout but not option scoring).
    if (tally is Map && tally['abstain'] != null) {
      final abstain = _asInt(tally['abstain']);
      if (abstain > 0) tallies['Abstain'] = abstain;
    }
    return OrganizerResults(tallies);
  }

  /// Decision options, from the cache or a public read (cached on the way).
  Future<List<String>> _optionsFor(String id) async {
    final cached = _options[id];
    if (cached != null) return cached;
    try {
      final d = await client.getDecision(id);
      final opts = d['options'];
      final list = opts is List
          ? opts.map((e) => e.toString()).toList()
          : <String>[];
      _options[id] = list;
      return list;
    } catch (_) {
      return const [];
    }
  }

  // ── OrganizerJourneyPort: phase actions ───────────────────────────────────

  @override
  Future<void> startVoting(String pollAddress) async {
    try {
      await client.openDecision(pollAddress);
    } on ServerException catch (e) {
      // Already open is fine (idempotent from the organizer's point of view);
      // an illegal transition from a non-draft state means voting is already
      // running, so swallow it rather than block the dashboard.
      if (e.code == 'ILLEGAL_TRANSITION') return;
      throw OrganizeWireException(
        _phaseCopy(e, 'Voting could not be started.'),
      );
    }
  }

  @override
  Future<void> endVoting(String pollAddress) async {
    try {
      await client.closeDecision(pollAddress);
    } on ServerException catch (e) {
      if (e.code == 'ILLEGAL_TRANSITION') return; // already closed
      throw OrganizeWireException(_phaseCopy(e, 'Voting could not be closed.'));
    }
  }

  /// Publish the closed decision (close→published in the server's lifecycle).
  /// Exposed for the console's publish step; the journey's publish flow is
  /// fetch-results, so this is called alongside it where wired.
  Future<void> publishDecision(String pollAddress) async {
    try {
      await client.publishDecision(pollAddress);
    } on ServerException catch (e) {
      if (e.code == 'ILLEGAL_TRANSITION') return; // already published
      throw OrganizeWireException(
        _phaseCopy(e, 'Results could not be published.'),
      );
    }
  }

  @override
  Future<void> finalize(String pollAddress) async {
    throw const OrganizeWireException(
      'Finalizing sealed-until-reveal results isn’t available on the '
      'open-ballot server (Phase 3).',
    );
  }

  String _phaseCopy(ServerException e, String fallback) {
    if (e.code == 'FORBIDDEN' || e.status == 401 || e.status == 403) {
      return 'This device isn’t signed in as the convener. Paste the admin '
          'token (Settings → Network) and try again.';
    }
    return e.message.isNotEmpty ? e.message : fallback;
  }

  // ── OrganizerConsolePort: dashboard cold loads ────────────────────────────

  @override
  Future<List<RunPollSnapshot>> loadCreatedPolls() async {
    final mine = await createdPolls.all();
    if (mine.isEmpty) return const [];
    final snapshots = <RunPollSnapshot>[];
    for (final id in mine) {
      final snapshot = await _snapshotFor(id);
      if (snapshot != null) snapshots.add(snapshot);
    }
    // createdPolls is an unordered set; newest-first isn't recoverable from it
    // alone, so the dashboard keeps insertion-agnostic order (the cards carry
    // their own state). Reverse to roughly surface later ids first.
    return snapshots.reversed.toList();
  }

  @override
  Future<RunPollSnapshot?> loadPoll(String pollAddress) =>
      _snapshotFor(pollAddress);

  Future<RunPollSnapshot?> _snapshotFor(String id) async {
    try {
      final d = await client.getDecision(id);
      final method = d['method'];
      final module = method is String ? moduleForServerMethod(method) : null;
      final opts = d['options'];
      if (opts is List) {
        _options[id] = opts.map((e) => e.toString()).toList();
      }
      final state = d['state'] is String ? d['state'] as String : 'draft';
      final phase = phaseForState(state);
      final turnout = _asInt(d['turnout']);
      return RunPollSnapshot(
        pollAddress: id,
        title: d['title'] is String ? d['title'] as String : '',
        module: module,
        phase: phase,
        // Open mode: turnout IS the participant signal (no separate roster).
        roster: turnout,
        turnout: phase >= 1 ? turnout : null,
        finalized: state == 'published',
        revealDeadline: 0,
      );
    } on ServerException catch (e) {
      // 404 → stale local record; skip, never brick the dashboard.
      if (e.status == 404 || e.code == 'NOT_FOUND') return null;
      return null;
    } catch (_) {
      return null;
    }
  }

  static int _asInt(Object? v) => switch (v) {
    int() => v,
    num() => v.toInt(),
    String() => int.tryParse(v) ?? 0,
    _ => 0,
  };
}

/// Builds a [ServerOrganizerPortAdapter] from the app config: a [ServerClient]
/// pointed at [AppConfig.serverUrl] carrying the in-memory convener token.
ServerOrganizerPortAdapter buildServerOrganizerPort({
  required CreatedPollsStore createdPolls,
  ServerClient? client,
}) {
  return ServerOrganizerPortAdapter(
    client:
        client ??
        ServerClient(
          baseUrl: AppConfig.serverUrl,
          token: AppConfig.convenerToken,
        ),
    createdPolls: createdPolls,
  );
}
