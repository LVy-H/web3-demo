import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/models/poll_info.dart';
import '../../core/dot_grid_background.dart';
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

enum _Status { active, upcoming, ended, all }

enum _Sort { newest, oldest, titleAsc, titleDesc }

class _BrowseScreenState extends State<BrowseScreen> {
  int _cat = -1; // -1 = all, else category index 0..3
  _Status _status = _Status.active;
  _Sort _sort = _Sort.newest;
  String _search = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => context.read<BrowseViewModel>().load());
  }

  // Real polls are all "active" (no on-chain end-time), matching the web client.
  PollPhase _phaseOf(PollInfo _) => PollPhase.active;

  List<PollInfo> _filterSort(List<PollInfo> polls) {
    final q = _search.trim().toLowerCase();
    final out = polls.where((p) {
      final catOk = _cat == -1 || Db.categoryFor(p.pollAddress) == _cat;
      final statusOk = _status == _Status.all ||
          (_status == _Status.active); // all real polls are active
      final searchOk = q.isEmpty ||
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
        out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
      case _Sort.titleDesc:
        out.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
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
              ViewState.idle || ViewState.loading => const Center(
                  child: CircularProgressIndicator(color: Db.segnale)),
              ViewState.error =>
                _ErrorView(message: vm.error ?? 'Unknown error', onRetry: vm.load),
              ViewState.loaded => _loaded(context, vm),
            },
          ),
        ),
      ),
    );
  }

  Widget _loaded(BuildContext context, BrowseViewModel vm) {
    final all = vm.polls;
    final filtered = _filterSort(all);
    final width = MediaQuery.sizeOf(context).width;
    final heroSize = (width * 0.08).clamp(40.0, 80.0);

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
                  horizontal: width < 600 ? 16 : 32, vertical: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Hero(heroSize: heroSize, total: all.length),
                  const SizedBox(height: 28),
                  _FilterStrip(
                    cat: _cat,
                    status: _status,
                    sort: _sort,
                    search: _search,
                    onCat: (c) => setState(() => _cat = c),
                    onStatus: (s) => setState(() => _status = s),
                    onSort: (s) => setState(() => _sort = s),
                    onSearch: (q) => setState(() => _search = q),
                  ),
                  const SizedBox(height: 24),
                  if (filtered.isEmpty)
                    const _EmptyView()
                  else
                    LayoutBuilder(builder: (context, c) {
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
                                phase: _phaseOf(p),
                              ),
                            ),
                        ],
                      );
                    }),
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
  const _Hero({required this.heroSize, required this.total});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('POLLS', style: dbHero(heroSize)),
              const SizedBox(height: 12),
              Text.rich(TextSpan(children: [
                const TextSpan(text: 'Active proposals across the community. '),
                TextSpan(
                  text: '$total total · $total active · 0 upcoming · 0 ended.',
                  style: dbSans(14, 400, Db.mute, height: 1.6),
                ),
              ]),
                  style: dbSans(14, 400, Db.chalkDim, height: 1.6)),
            ],
          ),
        ),
        const SizedBox(width: 16),
        _GhostButton(
          icon: Icons.add,
          label: 'NEW POLL',
          onTap: () => context.go('/create'),
        ),
      ],
    );
  }
}

class _GhostButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GhostButton(
      {required this.icon, required this.label, required this.onTap});
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: const BoxDecoration(
            color: Db.slate3,
            border: Border.fromBorderSide(BorderSide(color: Db.rule)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: Db.chalkDim),
            const SizedBox(width: 8),
            Text(label, style: dbLabel(size: 11, color: Db.chalkDim, tracking: 0.1)),
          ]),
        ),
      );
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
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _stripLabel('CATEGORY'),
          _Pill('All', cat == -1, () => onCat(-1)),
          for (var i = 0; i < 4; i++)
            _Pill(Db.categoryLabels[i].toUpperCase(), cat == i, () => onCat(i),
                swatch: Db.categoryColor(i)),
          _stripLabel('STATUS'),
          _Pill('ACTIVE', status == _Status.active, () => onStatus(_Status.active),
              activeColor: Db.segnale),
          _Pill('UPCOMING', status == _Status.upcoming,
              () => onStatus(_Status.upcoming)),
          _Pill('ENDED', status == _Status.ended, () => onStatus(_Status.ended)),
          _Pill('ALL', status == _Status.all, () => onStatus(_Status.all)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: SizedBox(
              width: 180,
              child: TextField(
                onChanged: onSearch,
                style: dbMono(11, Db.chalk, letterSpacing: 1.1),
                cursorColor: Db.segnale,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 15, color: Db.mute),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 28, minHeight: 28),
                  hintText: 'SEARCH POLLS',
                  hintStyle: dbLabel(size: 11, tracking: 0.1),
                  border: InputBorder.none,
                ),
              ),
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
  const _Pill(this.label, this.active, this.onTap,
      {this.swatch, this.activeColor = Db.slate});

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
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (swatch != null) ...[
            Container(width: 10, height: 3, color: active ? swatch : Db.muteDim),
            const SizedBox(width: 8),
          ],
          Text(label, style: dbLabel(size: 11, color: fg, tracking: 0.1)),
        ]),
      ),
    );
  }
}

class _PollCard extends StatefulWidget {
  final PollInfo poll;
  final int category;
  final PollPhase phase;
  const _PollCard(
      {required this.poll, required this.category, required this.phase});
  @override
  State<_PollCard> createState() => _PollCardState();
}

class _PollCardState extends State<_PollCard> {
  bool _hover = false;

  String get _shortCreator {
    final a = widget.poll.creator;
    return a.length > 12
        ? '${a.substring(0, 6)}·${a.substring(a.length - 4)}'.toUpperCase()
        : a.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final cat = Db.categoryColor(widget.category);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => context.go('/poll/${widget.poll.pollAddress}'),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(0, _hover ? -2 : 0, 0),
          constraints: const BoxConstraints(minHeight: 232),
          decoration: BoxDecoration(
            color: Db.slate,
            border: Border.all(color: _hover ? cat : Db.rule),
          ),
          child: Stack(
            children: [
              // top accent strip
              Positioned(
                  left: 0, right: 0, top: 0, height: 4, child: ColoredBox(color: cat)),
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
                    Row(children: [
                      Container(width: 8, height: 8, color: cat),
                      const SizedBox(width: 8),
                      Text(Db.categoryLabels[widget.category].toUpperCase(),
                          style: dbLabel(size: 10, color: cat, tracking: 0.22)),
                      const Spacer(),
                      const _StateChip(),
                    ]),
                    const SizedBox(height: 12),
                    Text(
                      widget.poll.title.isEmpty ? '(untitled)' : widget.poll.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: dbSans(19, 600, Db.chalk,
                          height: 1.28, letterSpacing: -0.1),
                    ),
                    const SizedBox(height: 10),
                    Text('$_shortCreator · OPENED RECENTLY',
                        style: dbMono(11, Db.mute, letterSpacing: 0.4)),
                    const SizedBox(height: 16),
                    const _HeroStat(),
                  ],
                ),
              ),
              Positioned(
                right: 14,
                bottom: 14,
                child: Icon(Icons.arrow_outward,
                    size: 18, color: _hover ? cat : Db.muteDim),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateChip extends StatelessWidget {
  const _StateChip();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: Db.segnale, border: Border.all(color: Db.segnale)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 6, height: 6, color: Db.chalk),
          const SizedBox(width: 6),
          Text('VOTING',
              style: dbLabel(size: 9.5, color: Db.chalk, tracking: 0.18, wght: 600)),
        ]),
      );
}

class _HeroStat extends StatelessWidget {
  const _HeroStat();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.only(top: 14),
        decoration:
            const BoxDecoration(border: Border(top: BorderSide(color: Db.ruleSoft))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic, children: [
          Text('—', style: dbSans(28, 700, Db.chalk, letterSpacing: -0.6)),
          const SizedBox(width: 8),
          Text('VOTES', style: dbLabel(size: 10)),
          const Spacer(),
          Text('T-MINUS —',
              style: dbMono(12, Db.segnale, letterSpacing: 1.0)),
        ]),
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
        child: Column(children: [
          const Icon(Icons.description_outlined, size: 44, color: Db.muteDim),
          const SizedBox(height: 14),
          Text('No polls match this filter',
              style: dbSans(18, 700, Db.chalk, letterSpacing: -0.2)),
          const SizedBox(height: 8),
          Text('FILTERS RETURNED 0 RESULTS', style: dbLabel(size: 11, tracking: 0.16)),
        ]),
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
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off, color: Db.segnale, size: 40),
            const SizedBox(height: 12),
            Text("COULDN'T LOAD POLLS", style: dbLabel(size: 12, color: Db.chalk)),
            const SizedBox(height: 8),
            Text(message,
                textAlign: TextAlign.center, style: dbMono(12, Db.mute)),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                shape: const RoundedRectangleBorder(),
                side: const BorderSide(color: Db.rule),
              ),
              child: Text('RETRY', style: dbLabel(size: 11, color: Db.chalk)),
            ),
          ]),
        ),
      );
}
