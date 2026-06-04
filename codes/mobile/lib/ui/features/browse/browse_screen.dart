import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/poll_info.dart';
import '../../../data/models/poll_summary.dart';
import '../../../data/services/chain_writer.dart';
import '../../../data/services/created_polls_store.dart';
import '../../../data/services/relay_client.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/poll_roles.dart';
import '../../core/theme.dart';
import '../../core/view_state.dart';
import '../../core/watermark.dart';
import 'browse_view_model.dart';

/// Browse all polls — Dark Bauhaus stateful-card grammar (port of web Home.tsx).
class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});
  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

enum _Status { active, upcoming, ended, mine, all }

enum _Sort { newest, oldest, titleAsc, titleDesc }

/// On-chain PollState → card lifecycle phase. Kept identical to the web client
/// (`Home.tsx`): Registration(0)→upcoming, Voting(1)→active, Ended(2)→ended.
PollPhase phaseFromState(int state) => switch (state) {
  1 => PollPhase.active,
  0 => PollPhase.upcoming,
  _ => PollPhase.ended,
};

class _BrowseScreenState extends State<BrowseScreen> {
  int _cat = -1; // -1 = all, else category index 0..3
  _Status _status = _Status.active;
  _Sort _sort = _Sort.newest;
  String _search = '';
  String?
  _relayerAddress; // labels relayer-owned (sponsored) polls on the cards
  Set<String> _createdPolls = {}; // addresses this device created (MINE filter)

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<BrowseViewModel>().load(),
    );
    // Resolve the relayer address so each card can read "SPONSORED" instead of
    // the same opaque hex on every wallet-free poll.
    context.read<RelayClient>().getRelayerInfo().then((info) {
      if (mounted) setState(() => _relayerAddress = info?.relayer);
    });
    _loadCreated();
  }

  Future<void> _loadCreated() async {
    final mine = await context.read<CreatedPollsStore>().all();
    if (mounted) setState(() => _createdPolls = mine);
  }

  // Lifecycle phase from the on-chain state (0 Registration→upcoming,
  // 1 Voting→active, 2 Ended→ended). Polls whose summary hasn't loaded fall
  // back to active so the card still renders a sensible look.
  PollPhase _phaseOf(PollInfo p, Map<String, PollSummary> sums) =>
      phaseFromState(sums[p.pollAddress]?.state ?? 1);

  bool _matchesStatus(PollPhase phase) => switch (_status) {
    _Status.all => true,
    _Status.active => phase == PollPhase.active,
    _Status.upcoming => phase == PollPhase.upcoming,
    _Status.ended => phase == PollPhase.ended,
    _Status.mine => true, // handled by the created-set check in _filterSort
  };

  List<PollInfo> _filterSort(
    List<PollInfo> polls,
    Map<String, PollSummary> sums,
  ) {
    final q = _search.trim().toLowerCase();
    final out = polls.where((p) {
      final catOk = _cat == -1 || Db.categoryFor(p.pollAddress) == _cat;
      final statusOk = _status == _Status.mine
          ? _createdPolls.contains(p.pollAddress.toLowerCase())
          : _matchesStatus(_phaseOf(p, sums));
      final searchOk =
          q.isEmpty ||
          p.title.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q);
      return catOk && statusOk && searchOk;
    }).toList();
    switch (_sort) {
      case _Sort.newest:
        out.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _Sort.oldest:
        out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      case _Sort.titleAsc:
        out.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
      case _Sort.titleDesc:
        out.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Consumer<BrowseViewModel>(
            builder: (context, vm, _) => switch (vm.state) {
              ViewState.idle || ViewState.loading => const _LoadingView(),
              ViewState.error => _ErrorView(
                message: vm.error ?? 'Unknown error',
                onRetry: vm.load,
              ),
              ViewState.loaded => _loaded(context, vm),
            },
          ),
        ),
      ),
    );
  }

  Widget _loaded(BuildContext context, BrowseViewModel vm) {
    final all = vm.polls;
    final sums = vm.summaries;
    final filtered = _filterSort(all, sums);
    final width = MediaQuery.sizeOf(context).width;
    final heroSize = (width * 0.08).clamp(40.0, 80.0);

    // Phase tallies for the hero subtitle (from loaded summaries).
    var active = 0, upcoming = 0, ended = 0;
    for (final p in all) {
      switch (_phaseOf(p, sums)) {
        case PollPhase.active:
          active++;
        case PollPhase.upcoming:
          upcoming++;
        case PollPhase.ended:
          ended++;
      }
    }

    return RefreshIndicator(
      color: Db.segnale,
      backgroundColor: Db.slate,
      onRefresh: vm.load,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: width < 600 ? 16 : 32,
                vertical: 28,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Hero(
                    heroSize: heroSize,
                    total: all.length,
                    active: active,
                    upcoming: upcoming,
                    ended: ended,
                  ),
                  const SizedBox(height: 28),
                  _FilterStrip(
                    cat: _cat,
                    status: _status,
                    sort: _sort,
                    search: _search,
                    onCat: (c) => setState(() => _cat = c),
                    onStatus: (s) {
                      setState(() => _status = s);
                      if (s == _Status.mine) _loadCreated(); // refresh "mine"
                    },
                    onSort: (s) => setState(() => _sort = s),
                    onSearch: (q) => setState(() => _search = q),
                  ),
                  const SizedBox(height: 24),
                  if (filtered.isEmpty)
                    const _EmptyView()
                  else
                    LayoutBuilder(
                      builder: (context, c) {
                        final cols = (c.maxWidth / 340).floor().clamp(1, 3);
                        const gap = 16.0;
                        final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
                        return Wrap(
                          spacing: gap,
                          runSpacing: gap,
                          children: [
                            for (final p in filtered)
                              SizedBox(
                                width: itemW,
                                child: _PollCard(
                                  poll: p,
                                  category: Db.categoryFor(p.pollAddress),
                                  phase: _phaseOf(p, sums),
                                  votes: sums[p.pollAddress]?.totalVotes,
                                  relayerAddress: _relayerAddress,
                                  myAddress: context
                                      .read<ChainWriter>()
                                      .signerAddress,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 20),
                  if (filtered.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        'SHOWING ${filtered.length} OF ${all.length} POLLS',
                        style: dbLabel(size: 11, tracking: 0.14),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final double heroSize;
  final int total;
  final int active;
  final int upcoming;
  final int ended;
  const _Hero({
    required this.heroSize,
    required this.total,
    required this.active,
    required this.upcoming,
    required this.ended,
  });

  @override
  Widget build(BuildContext context) {
    // Nav (Verify / Create) lives in the bottom NavigationBar and the wallet
    // button in the drawer now (see AppShell), so the hero is just the title.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('POLLS', style: dbHero(heroSize)),
        const SizedBox(height: 12),
        Text.rich(
          TextSpan(
            children: [
              const TextSpan(text: 'Active proposals across the community. '),
              TextSpan(
                text:
                    '$total total · $active active · $upcoming upcoming · $ended ended.',
                style: dbSans(14, 400, Db.mute, height: 1.6),
              ),
            ],
          ),
          style: dbSans(14, 400, Db.chalkDim, height: 1.6),
        ),
      ],
    );
  }
}

class _FilterStrip extends StatelessWidget {
  final int cat;
  final _Status status;
  final _Sort sort;
  final String search;
  final ValueChanged<int> onCat;
  final ValueChanged<_Status> onStatus;
  final ValueChanged<_Sort> onSort;
  final ValueChanged<String> onSearch;
  const _FilterStrip({
    required this.cat,
    required this.status,
    required this.sort,
    required this.search,
    required this.onCat,
    required this.onStatus,
    required this.onSort,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Db.slate3,
        border: Border.fromBorderSide(BorderSide(color: Db.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search on its own full-width row.
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
            child: TextField(
              onChanged: onSearch,
              style: dbMono(12, Db.chalk, letterSpacing: 1.0),
              cursorColor: Db.segnale,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 16, color: Db.mute),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 30,
                  minHeight: 30,
                ),
                hintText: 'SEARCH POLLS',
                hintStyle: dbLabel(size: 11, tracking: 0.1),
                border: InputBorder.none,
              ),
            ),
          ),
          const Divider(height: 1, color: Db.rule),
          // Filters as ONE horizontally-scrollable row — never wraps into a
          // tall, overwhelming block on a phone.
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _stripLabel('STATUS'),
                _Pill(
                  'ACTIVE',
                  status == _Status.active,
                  () => onStatus(_Status.active),
                  activeColor: Db.segnale,
                ),
                _Pill(
                  'UPCOMING',
                  status == _Status.upcoming,
                  () => onStatus(_Status.upcoming),
                ),
                _Pill(
                  'ENDED',
                  status == _Status.ended,
                  () => onStatus(_Status.ended),
                ),
                _Pill(
                  'MINE',
                  status == _Status.mine,
                  () => onStatus(_Status.mine),
                  activeColor: Db.success,
                ),
                _Pill(
                  'ALL',
                  status == _Status.all,
                  () => onStatus(_Status.all),
                ),
                _stripLabel('CATEGORY'),
                _Pill('All', cat == -1, () => onCat(-1)),
                for (var i = 0; i < 4; i++)
                  _Pill(
                    Db.categoryLabels[i].toUpperCase(),
                    cat == i,
                    () => onCat(i),
                    swatch: Db.categoryColor(i),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stripLabel(String t) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: const BoxDecoration(
      border: Border(right: BorderSide(color: Db.rule)),
    ),
    child: Text(t, style: dbLabel(size: 10)),
  );
}

class _Pill extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  final Color? swatch;
  final Color activeColor;
  const _Pill(
    this.label,
    this.active,
    this.onTap, {
    this.swatch,
    this.activeColor = Db.slate,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? (activeColor == Db.segnale ? Db.segnale : Db.slate)
        : Colors.transparent;
    final fg = active
        ? (activeColor == Db.segnale ? Db.chalk : Db.chalk)
        : Db.chalkDim;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          border: const Border(right: BorderSide(color: Db.rule)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (swatch != null) ...[
              Container(
                width: 10,
                height: 3,
                color: active ? swatch : Db.muteDim,
              ),
              const SizedBox(width: 8),
            ],
            Text(label, style: dbLabel(size: 11, color: fg, tracking: 0.1)),
          ],
        ),
      ),
    );
  }
}

class _PollCard extends StatefulWidget {
  final PollInfo poll;
  final int category;
  final PollPhase phase;
  final BigInt? votes; // null = summary not loaded yet
  final String? relayerAddress;
  final String? myAddress;
  const _PollCard({
    required this.poll,
    required this.category,
    required this.phase,
    this.votes,
    this.relayerAddress,
    this.myAddress,
  });
  @override
  State<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<_PollCard> {
  bool _hover = false;

  // A short ownership tag for the card: a wallet-free poll reads SPONSORED (the
  // relayer runs it) instead of an opaque hex repeated on every card; your own
  // reads YOU; otherwise the creator's short address.
  String get _ownerLabel {
    final o = pollOwner(
      owner: widget.poll.creator,
      relayerAddress: widget.relayerAddress,
      myAddress: widget.myAddress,
    );
    return switch (o.kind) {
      PollOwnerKind.sponsored => 'SPONSORED',
      PollOwnerKind.you => 'YOU',
      PollOwnerKind.other => shortAddr(widget.poll.creator).toUpperCase(),
    };
  }

  // Surface tint per phase, matching the web (bg-db-slate / slate-2 / slate-dim).
  Color get _surface => switch (widget.phase) {
    PollPhase.active => Db.slate,
    PollPhase.upcoming => Db.slate2,
    PollPhase.ended => Db.slateDim,
  };

  @override
  Widget build(BuildContext context) {
    final cat = Db.categoryColor(widget.category);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go(
          '/poll/${widget.poll.pollAddress}?module=${widget.poll.moduleType}',
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          constraints: const BoxConstraints(minHeight: 232),
          decoration: BoxDecoration(
            color: _surface,
            border: Border.all(color: _hover ? cat : Db.rule),
          ),
          child: Stack(
            children: [
              // top accent strip
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                height: 4,
                child: ColoredBox(color: cat),
              ),
              // watermark
              Positioned(
                right: -10,
                bottom: -12,
                child: Watermark(phase: widget.phase, size: 140),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 8, height: 8, color: cat),
                        const SizedBox(width: 8),
                        Text(
                          Db.categoryLabels[widget.category].toUpperCase(),
                          style: dbLabel(size: 10, color: cat, tracking: 0.22),
                        ),
                        const Spacer(),
                        _StateChip(phase: widget.phase),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.poll.title.isEmpty
                          ? '(untitled)'
                          : widget.poll.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: dbSans(
                        19,
                        600,
                        Db.chalk,
                        height: 1.28,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      '$_ownerLabel · OPENED RECENTLY',
                      style: dbMono(11, Db.mute, letterSpacing: 0.4),
                    ),
                    const SizedBox(height: 16),
                    _HeroStat(votes: widget.votes),
                  ],
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Icon(
                  Icons.arrow_outward,
                  size: 18,
                  color: _hover ? cat : Db.muteDim,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  final PollPhase phase;
  const _StateChip({required this.phase});

  // (label, fill, border, ink, dot) per phase — matches web Home.tsx StateChip.
  ({String label, Color fill, Color border, Color ink, Color dot}) get _spec =>
      switch (phase) {
        PollPhase.active => (
          label: 'VOTING',
          fill: Db.segnale,
          border: Db.segnale,
          ink: Db.chalk,
          dot: Db.chalk,
        ),
        PollPhase.upcoming => (
          label: 'UPCOMING',
          fill: Colors.transparent,
          border: Db.oltremare,
          ink: Db.oltremare,
          dot: Db.oltremare,
        ),
        PollPhase.ended => (
          label: 'ENDED',
          fill: Db.slate4,
          border: Db.rule,
          ink: Db.mute,
          dot: Db.muteDim,
        ),
      };

  @override
  Widget build(BuildContext context) {
    final s = _spec;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: s.fill,
        border: Border.all(color: s.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, color: s.dot),
          const SizedBox(width: 6),
          Text(
            s.label,
            style: dbLabel(size: 9.5, color: s.ink, tracking: 0.18, wght: 600),
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final BigInt? votes;
  const _HeroStat({this.votes});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.only(top: 14),
    decoration: const BoxDecoration(
      border: Border(top: BorderSide(color: Db.ruleSoft)),
    ),
    // Just the vote tally. The old trailing 'T-MINUS —' was a half-wired
    // countdown that only ever rendered an em-dash (these poll types carry no
    // deadline), and on a narrow card it overflowed the row. The poll's phase
    // is already shown honestly by the _StateChip at the top of the card, so
    // a second status word here would be redundant — dropped entirely. The
    // big number is Flexible+ellipsis so a huge tally can't overflow either.
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: Text(
            votes?.toString() ?? '—',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: dbSans(28, 700, Db.chalk, letterSpacing: -0.6),
          ),
        ),
        const SizedBox(width: 8),
        Text('VOTES', style: dbLabel(size: 10)),
      ],
    ),
  );
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
    decoration: const BoxDecoration(
      color: Db.slate3,
      border: Border.fromBorderSide(BorderSide(color: Db.rule)),
    ),
    child: Column(
      children: [
        const Icon(Icons.description_outlined, size: 44, color: Db.muteDim),
        const SizedBox(height: 14),
        Text(
          'No polls match this filter',
          style: dbSans(18, 700, Db.chalk, letterSpacing: -0.2),
        ),
        const SizedBox(height: 8),
        Text(
          'FILTERS RETURNED 0 RESULTS',
          style: dbLabel(size: 11, tracking: 0.16),
        ),
      ],
    ),
  );
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return SingleChildScrollView(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: width < 600 ? 16 : 32,
              vertical: 28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(width: 220, height: 56, color: Db.slate),
                const SizedBox(height: 28),
                LayoutBuilder(
                  builder: (context, c) {
                    final cols = (c.maxWidth / 340).floor().clamp(1, 3);
                    const gap = 16.0;
                    final itemW = (c.maxWidth - gap * (cols - 1)) / cols;
                    return Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (var i = 0; i < cols * 2; i++)
                          SizedBox(width: itemW, child: const _SkeletonCard()),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();
  static Widget _bar(double w, double h) =>
      Container(width: w, height: h, color: Db.ruleSoft);
  @override
  Widget build(BuildContext context) => Container(
    height: 232,
    decoration: BoxDecoration(
      color: Db.slate,
      border: Border.all(color: Db.rule),
    ),
    child: Stack(
      children: [
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: 4,
          child: ColoredBox(color: Db.rule),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _bar(80, 10),
              const SizedBox(height: 18),
              _bar(double.infinity, 18),
              const SizedBox(height: 8),
              _bar(150, 18),
              const Spacer(),
              _bar(120, 12),
            ],
          ),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, color: Db.segnale, size: 40),
          const SizedBox(height: 12),
          Text(
            "COULDN'T LOAD POLLS",
            style: dbLabel(size: 12, color: Db.chalk),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: dbMono(12, Db.mute),
          ),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: onRetry,
            style: OutlinedButton.styleFrom(
              shape: const RoundedRectangleBorder(),
              side: const BorderSide(color: Db.rule),
            ),
            child: Text('RETRY', style: dbLabel(size: 11, color: Db.chalk)),
          ),
        ],
      ),
    ),
  );
}
