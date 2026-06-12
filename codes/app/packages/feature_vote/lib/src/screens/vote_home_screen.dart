/// The VOTE space — the app's default screen (spec §4.1).
///
/// MY VOTES: the polls this device joined, bucketed by what the voter
/// journey can do RIGHT NOW (local record + a cheap phase read per poll):
///   NEEDS YOU — actionable (voting open and not voted; sealed vote awaiting
///               confirmation after close)
///   WAITING   — joined but voting not open; locked in, voting still open
///   DONE      — receipt chips (and ended polls)
/// DIRECTORY: the opt-in listed polls (private-by-default means this is the
/// exception, not the home).
library;

import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import '../copy.dart';
import '../data/known_polls_store.dart';
import '../data/listed_polls_reader.dart';

/// One bucketed row of the MY VOTES list.
class VoteHomeEntry {
  final KnownPoll poll;

  /// Chain phase (0/1/2) or null when unreachable.
  final int? phase;

  const VoteHomeEntry({required this.poll, required this.phase});

  /// What the home says this poll needs, jargon-free.
  String get statusLine {
    if (poll.stage == KnownPollStage.voted) {
      return poll.receiptCode != null ? 'VOTED — RECEIPT SAVED' : 'DONE';
    }
    if (phase == null) return 'CAN’T CHECK RIGHT NOW';
    if (poll.stage == KnownPollStage.committed) {
      return phase == 2 ? 'CONFIRM YOUR VOTE NOW' : 'LOCKED IN — WAITING';
    }
    return switch (phase) {
      0 => 'JOINED — VOTING NOT OPEN YET',
      1 => 'VOTING IS OPEN',
      _ => 'ENDED',
    };
  }
}

enum VoteHomeSection { needsYou, waiting, done }

/// Pure bucketing — unit-testable without widgets.
VoteHomeSection sectionFor(KnownPoll poll, int? phase) {
  if (poll.stage == KnownPollStage.voted) return VoteHomeSection.done;
  if (poll.stage == KnownPollStage.committed) {
    // Committed blind votes become actionable when the poll ends (the
    // confirmation window opens); until then they wait.
    return phase == 2 ? VoteHomeSection.needsYou : VoteHomeSection.waiting;
  }
  return switch (phase) {
    1 => VoteHomeSection.needsYou,
    2 => VoteHomeSection.done, // ended before this device voted
    _ => VoteHomeSection.waiting, // not open yet, or unreachable
  };
}

class VoteHomeScreen extends StatefulWidget {
  final KnownPollsStore knownPolls;

  /// Cheap per-poll phase read (production: `ChainReader.getState`).
  final Future<int> Function(String address) fetchPhase;

  /// The opt-in public directory (production: [ListedPollsReader.fetchListed]).
  final Future<List<ListedPoll>> Function() fetchDirectory;

  final void Function(String address) onOpenPoll;
  final VoidCallback onJoin;

  const VoteHomeScreen({
    super.key,
    required this.knownPolls,
    required this.fetchPhase,
    required this.fetchDirectory,
    required this.onOpenPoll,
    required this.onJoin,
  });

  static const emptyStateKey = Key('vote-home-empty');
  static const myVotesTabKey = Key('vote-home-tab-mine');
  static const directoryTabKey = Key('vote-home-tab-directory');

  @override
  State<VoteHomeScreen> createState() => _VoteHomeScreenState();
}

class _VoteHomeScreenState extends State<VoteHomeScreen> {
  int _tab = 0;
  late Future<List<VoteHomeEntry>> _entries;

  // Directory state is explicit (not a FutureBuilder) so a failing fetch is
  // always caught here — never an unhandled async error.
  bool _directoryStarted = false;
  bool _directoryLoading = false;
  bool _directoryFailed = false;
  List<ListedPoll>? _directoryPolls;

  @override
  void initState() {
    super.initState();
    _entries = _load();
  }

  Future<void> _loadDirectory() async {
    setState(() {
      _directoryStarted = true;
      _directoryLoading = true;
      _directoryFailed = false;
    });
    try {
      final polls = await widget.fetchDirectory();
      if (!mounted) return;
      setState(() {
        _directoryPolls = polls;
        _directoryLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _directoryFailed = true;
        _directoryLoading = false;
      });
    }
  }

  Future<List<VoteHomeEntry>> _load() async {
    final polls = await widget.knownPolls.all();
    final entries = <VoteHomeEntry>[];
    for (final poll in polls) {
      int? phase;
      try {
        phase = await widget.fetchPhase(poll.address);
      } catch (_) {
        phase = null; // unreachable chain: shown honestly, never a crash
      }
      entries.add(VoteHomeEntry(poll: poll, phase: phase));
    }
    return entries;
  }

  void _refresh() => setState(() => _entries = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    body: DotGridBackground(
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Row(
                    children: [
                      Text('VOTE', style: dbSans(34, 800, Db.chalk)),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Refresh',
                        icon: const Icon(
                          Icons.refresh,
                          size: 20,
                          color: Db.mute,
                        ),
                        onPressed: _refresh,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    children: [
                      _TabButton(
                        key: VoteHomeScreen.myVotesTabKey,
                        label: 'MY VOTES',
                        selected: _tab == 0,
                        onTap: () => setState(() => _tab = 0),
                      ),
                      const SizedBox(width: 10),
                      _TabButton(
                        key: VoteHomeScreen.directoryTabKey,
                        label: 'DIRECTORY',
                        selected: _tab == 1,
                        onTap: () {
                          setState(() => _tab = 1);
                          if (!_directoryStarted) _loadDirectory();
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(child: _tab == 0 ? _myVotes() : _directoryList()),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  // ── MY VOTES ────────────────────────────────────────────────────────────

  Widget _myVotes() => FutureBuilder<List<VoteHomeEntry>>(
    future: _entries,
    builder: (context, snap) {
      final entries = snap.data;
      if (entries == null) {
        return const Center(
          child: CircularProgressIndicator(color: Db.segnale),
        );
      }
      if (entries.isEmpty) return _empty();

      final needsYou = [
        for (final e in entries)
          if (sectionFor(e.poll, e.phase) == VoteHomeSection.needsYou) e,
      ];
      final waiting = [
        for (final e in entries)
          if (sectionFor(e.poll, e.phase) == VoteHomeSection.waiting) e,
      ];
      final done = [
        for (final e in entries)
          if (sectionFor(e.poll, e.phase) == VoteHomeSection.done) e,
      ];

      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
        children: [
          if (needsYou.isNotEmpty) ...[
            _sectionHeader('NEEDS YOU', Db.segnale, needsYou.length),
            for (final e in needsYou) _entryCard(e, highlight: true),
            const SizedBox(height: 18),
          ],
          if (waiting.isNotEmpty) ...[
            _sectionHeader('WAITING', Db.oltremare, waiting.length),
            for (final e in waiting) _entryCard(e),
            const SizedBox(height: 18),
          ],
          if (done.isNotEmpty) ...[
            _sectionHeader('DONE', Db.mute, done.length),
            for (final e in done) _entryCard(e),
          ],
        ],
      );
    },
  );

  Widget _sectionHeader(String label, Color color, int count) => Padding(
    padding: const EdgeInsets.only(bottom: 10, top: 4),
    child: Row(
      children: [
        Container(width: 8, height: 8, color: color),
        const SizedBox(width: 8),
        Text(label, style: dbLabel(size: 10, color: color)),
        const SizedBox(width: 8),
        Text('$count', style: dbMono(10, Db.mute)),
      ],
    ),
  );

  Widget _entryCard(VoteHomeEntry entry, {bool highlight = false}) {
    final poll = entry.poll;
    return InkWell(
      onTap: () => widget.onOpenPoll(poll.address),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: highlight ? Db.slate : Db.slateDim,
          border: Border.all(color: highlight ? Db.segnale : Db.rule),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    poll.title.isEmpty ? 'Untitled vote' : poll.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: dbSans(15, 800, Db.chalk),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  voteKindLabel(poll.moduleType),
                  style: dbLabel(size: 8, color: Db.mute),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.statusLine,
              style: dbMono(
                10,
                highlight ? Db.segnale : Db.mute,
                wght: 700,
                letterSpacing: 0.8,
              ),
            ),
            if (poll.receiptCode != null) ...[
              const SizedBox(height: 10),
              _receiptChip(poll.receiptCode!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _receiptChip(String code) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: Db.slate4,
      border: Border.all(color: Db.ruleSoft),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.receipt_long, size: 12, color: Db.success),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'RECEIPT ${code.length > 10 ? '${code.substring(0, 10)}…' : code}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dbMono(9, Db.chalkDim, wght: 700, letterSpacing: 0.6),
          ),
        ),
      ],
    ),
  );

  Widget _empty() => Center(
    key: VoteHomeScreen.emptyStateKey,
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.how_to_vote_outlined, size: 44, color: Db.mute),
          const SizedBox(height: 16),
          Text(
            'Nothing to vote on yet',
            style: dbSans(18, 800, Db.chalk),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Scan or paste an invite to join your first vote.',
            style: dbMono(12, Db.mute, height: 1.6),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          InkWell(
            onTap: widget.onJoin,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
              decoration: BoxDecoration(
                color: Db.segnale,
                border: Border.all(color: Db.segnale),
              ),
              child: Text(
                'JOIN A VOTE',
                style: dbSans(12, 800, Db.void_, letterSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    ),
  );

  // ── DIRECTORY ───────────────────────────────────────────────────────────

  Widget _directoryList() {
    if (_directoryFailed) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Could not load the directory. Check your connection.',
              style: dbMono(12, Db.mute, height: 1.6),
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              onPressed: _loadDirectory,
              style: OutlinedButton.styleFrom(
                foregroundColor: Db.segnale,
                side: const BorderSide(color: Db.segnale),
                shape: const RoundedRectangleBorder(),
              ),
              child: Text(
                'TRY AGAIN',
                style: dbMono(11, Db.segnale, wght: 700),
              ),
            ),
          ],
        ),
      );
    }
    final polls = _directoryPolls;
    if (_directoryLoading || polls == null) {
      return const Center(child: CircularProgressIndicator(color: Db.segnale));
    }
    if (polls.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'No public votes right now. Most votes are private — you join '
          'those with an invite.',
          style: dbMono(12, Db.mute, height: 1.6),
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 96),
      children: [
        for (final poll in polls)
          InkWell(
            onTap: () => widget.onOpenPoll(poll.address),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Db.slate2,
                border: Border.all(color: Db.rule),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          poll.title.isEmpty ? 'Untitled vote' : poll.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: dbSans(15, 800, Db.chalk),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        voteKindLabel(poll.moduleType),
                        style: dbLabel(size: 8, color: Db.segnale),
                      ),
                    ],
                  ),
                  if (poll.description.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      poll.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: dbMono(11, Db.mute, height: 1.5),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TabButton({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? Db.segnale : Db.void_,
        border: Border.all(color: selected ? Db.segnale : Db.rule),
      ),
      child: Text(
        label,
        style: dbSans(11, 800, selected ? Db.void_ : Db.mute, letterSpacing: 1),
      ),
    ),
  );
}
