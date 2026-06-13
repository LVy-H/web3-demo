/// Module ballot inputs — visuals per design_system, validity per the
/// journey machine's [BallotSpec] rules.
///
/// Each ballot owns its local selection and reports `onChanged` with a VALID
/// [BallotSpec], or `null` while the selection is incomplete/invalid — the
/// screen only ever dispatches valid specs into the machine (an invalid
/// `VoterBallotEdited` would throw `JourneyViolation` by design).
library;

import 'package:core_domain/journeys/voter_journey.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import '../../data/survey_reader.dart';

typedef BallotChanged = void Function(BallotSpec? spec);

/// Sharp option tile shared by the choice-style ballots.
class _OptionTile extends StatelessWidget {
  final String label;
  final bool selected;
  final Widget leading;
  final VoidCallback onTap;

  const _OptionTile({
    required this.label,
    required this.selected,
    required this.leading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Semantics(
    // A choice tile is a selectable control: assistive tech must announce the
    // option label, that it's tappable, and whether it's currently chosen —
    // the leading radio/checkbox glyph is purely visual.
    button: true,
    selected: selected,
    label: label,
    excludeSemantics: true,
    onTap: onTap,
    child: InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: selected ? Db.slate2 : Db.void_,
          border: Border.all(color: selected ? Db.segnale : Db.rule),
        ),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: dbSans(14, selected ? 800 : 600, Db.chalk),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// `anon` — pick one (radio list).
class SingleChoiceBallot extends StatefulWidget {
  final List<String> options;
  final BallotChanged onChanged;
  final SingleChoice? initial;

  const SingleChoiceBallot({
    super.key,
    required this.options,
    required this.onChanged,
    this.initial,
  });

  @override
  State<SingleChoiceBallot> createState() => _SingleChoiceBallotState();
}

class _SingleChoiceBallotState extends State<SingleChoiceBallot> {
  int? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial?.optionIndex;
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < widget.options.length; i++)
        _OptionTile(
          label: widget.options[i],
          selected: _selected == i,
          leading: Icon(
            _selected == i
                ? Icons.radio_button_checked
                : Icons.radio_button_off,
            size: 18,
            color: _selected == i ? Db.segnale : Db.mute,
          ),
          onTap: () {
            setState(() => _selected = i);
            widget.onChanged(SingleChoice(i));
          },
        ),
    ],
  );
}

/// `approval` — approve any (checkbox list → bitmask).
class ApprovalBallot extends StatefulWidget {
  final List<String> options;
  final BallotChanged onChanged;
  final Approval? initial;

  const ApprovalBallot({
    super.key,
    required this.options,
    required this.onChanged,
    this.initial,
  });

  @override
  State<ApprovalBallot> createState() => _ApprovalBallotState();
}

class _ApprovalBallotState extends State<ApprovalBallot> {
  late final Set<int> _approved = {
    if (widget.initial != null)
      for (var i = 0; i < widget.options.length; i++)
        if (widget.initial!.bitmask >> i & BigInt.one == BigInt.one) i,
  };

  void _toggle(int i) {
    setState(
      () => _approved.contains(i) ? _approved.remove(i) : _approved.add(i),
    );
    var mask = BigInt.zero;
    for (final bit in _approved) {
      mask |= BigInt.one << bit;
    }
    widget.onChanged(mask > BigInt.zero ? Approval(mask) : null);
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      for (var i = 0; i < widget.options.length; i++)
        _OptionTile(
          label: widget.options[i],
          selected: _approved.contains(i),
          leading: Icon(
            _approved.contains(i)
                ? Icons.check_box
                : Icons.check_box_outline_blank,
            size: 18,
            color: _approved.contains(i) ? Db.segnale : Db.mute,
          ),
          onTap: () => _toggle(i),
        ),
    ],
  );
}

/// `ranked` — drag to order. The current order IS the ballot; confirm it once
/// (or drag) to make it the draft.
class RankedBallot extends StatefulWidget {
  final List<String> options;
  final BallotChanged onChanged;
  final Ranked? initial;

  const RankedBallot({
    super.key,
    required this.options,
    required this.onChanged,
    this.initial,
  });

  static const confirmOrderKey = Key('ranked-confirm-order');

  @override
  State<RankedBallot> createState() => _RankedBallotState();
}

class _RankedBallotState extends State<RankedBallot> {
  late List<int> _order;
  late bool _confirmed;

  @override
  void initState() {
    super.initState();
    _order =
        widget.initial?.ordering.toList() ??
        List.generate(widget.options.length, (i) => i);
    _confirmed = widget.initial != null;
  }

  void _emit() {
    _confirmed = true;
    widget.onChanged(Ranked(_order));
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Drag your favorite to the top.',
        style: dbMono(11, Db.mute, height: 1.5),
      ),
      const SizedBox(height: 10),
      ReorderableListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        buildDefaultDragHandles: false,
        onReorder: (from, to) {
          setState(() {
            if (to > from) to -= 1;
            final moved = _order.removeAt(from);
            _order.insert(to, moved);
          });
          _emit();
        },
        children: [
          for (var pos = 0; pos < _order.length; pos++)
            ReorderableDragStartListener(
              key: ValueKey('rank-${_order[pos]}'),
              index: pos,
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: Db.void_,
                  border: Border.all(color: Db.rule),
                ),
                child: Row(
                  children: [
                    Text(
                      '${pos + 1}',
                      style: dbMono(13, Db.segnale, wght: 700),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.options[_order[pos]],
                        style: dbSans(14, 700, Db.chalk),
                      ),
                    ),
                    const Icon(Icons.drag_handle, size: 18, color: Db.mute),
                  ],
                ),
              ),
            ),
        ],
      ),
      if (!_confirmed)
        InkWell(
          key: RankedBallot.confirmOrderKey,
          onTap: () => setState(_emit),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Db.void_,
              border: Border.all(color: Db.segnale),
            ),
            child: Text(
              'USE THIS ORDER',
              style: dbSans(11, 800, Db.segnale, letterSpacing: 1),
            ),
          ),
        ),
    ],
  );
}

/// `quadratic` — split 100 points with steppers + a live credit meter.
class QuadraticBallot extends StatefulWidget {
  final List<String> options;
  final BallotChanged onChanged;
  final Quadratic? initial;

  const QuadraticBallot({
    super.key,
    required this.options,
    required this.onChanged,
    this.initial,
  });

  static Key plusKey(int i) => Key('quadratic-plus-$i');
  static Key minusKey(int i) => Key('quadratic-minus-$i');
  static const meterKey = Key('quadratic-credit-meter');

  @override
  State<QuadraticBallot> createState() => _QuadraticBallotState();
}

class _QuadraticBallotState extends State<QuadraticBallot> {
  late List<int> _votes;

  @override
  void initState() {
    super.initState();
    _votes =
        widget.initial?.alloc.toList() ?? List.filled(widget.options.length, 0);
    while (_votes.length < widget.options.length) {
      _votes.add(0);
    }
  }

  int get _cost => _votes.fold(0, (sum, v) => sum + v * v);

  void _bump(int i, int delta) {
    final next = _votes[i] + delta;
    if (next < 0 || next > Quadratic.maxVotesPerOption) return;
    final spec = Quadratic([
      for (var j = 0; j < _votes.length; j++) j == i ? next : _votes[j],
    ]);
    if (spec.cost > Quadratic.credits) return; // never exceed the budget
    setState(() => _votes[i] = next);
    widget.onChanged(_votes.any((v) => v > 0) ? Quadratic(_votes) : null);
  }

  @override
  Widget build(BuildContext context) {
    final remaining = Quadratic.credits - _cost;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          key: QuadraticBallot.meterKey,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Db.slate3,
            border: Border.all(color: Db.rule),
          ),
          child: Row(
            children: [
              Text('POINTS LEFT', style: dbLabel(size: 9)),
              const Spacer(),
              Text(
                '$remaining / ${Quadratic.credits}',
                style: dbMono(
                  13,
                  remaining == 0 ? Db.segnale : Db.chalk,
                  wght: 700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Backing one choice harder costs more: 1 vote = 1 point, '
          '2 votes = 4 points, 3 votes = 9…',
          style: dbMono(10, Db.mute, height: 1.5),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < widget.options.length; i++)
          Semantics(
            // The row reads as "{option}: {n} points" so a screen-reader voter
            // always knows the current allocation; the +/- buttons keep their
            // own labels (below) and the bare digit Text is folded into this.
            container: true,
            label: '${widget.options[i]}: ${_votes[i]} points',
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _votes[i] > 0 ? Db.slate2 : Db.void_,
                border: Border.all(color: _votes[i] > 0 ? Db.segnale : Db.rule),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: ExcludeSemantics(
                      child: Text(
                        widget.options[i],
                        style: dbSans(14, _votes[i] > 0 ? 800 : 600, Db.chalk),
                      ),
                    ),
                  ),
                  IconButton(
                    key: QuadraticBallot.minusKey(i),
                    tooltip: 'Remove a point from ${widget.options[i]}',
                    onPressed: _votes[i] > 0 ? () => _bump(i, -1) : null,
                    icon: const Icon(Icons.remove, size: 18),
                    color: Db.chalkDim,
                    disabledColor: Db.rule,
                  ),
                  SizedBox(
                    width: 28,
                    child: ExcludeSemantics(
                      child: Text(
                        '${_votes[i]}',
                        textAlign: TextAlign.center,
                        style: dbMono(15, Db.chalk, wght: 700),
                      ),
                    ),
                  ),
                  IconButton(
                    key: QuadraticBallot.plusKey(i),
                    tooltip: 'Add a point to ${widget.options[i]}',
                    onPressed: () => _bump(i, 1),
                    icon: const Icon(Icons.add, size: 18),
                    color: Db.chalkDim,
                    disabledColor: Db.rule,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// `survey` — one question per page; the ballot is the full answer vector.
class SurveyBallot extends StatefulWidget {
  final SurveyDetails details;
  final BallotChanged onChanged;

  const SurveyBallot({
    super.key,
    required this.details,
    required this.onChanged,
  });

  static const nextQuestionKey = Key('survey-next-question');
  static const previousQuestionKey = Key('survey-previous-question');

  @override
  State<SurveyBallot> createState() => _SurveyBallotState();
}

class _SurveyBallotState extends State<SurveyBallot> {
  int _page = 0;
  late final List<int?> _single = List.filled(
    widget.details.questionCount,
    null,
  );
  late final List<Set<int>> _multi = List.generate(
    widget.details.questionCount,
    (_) => <int>{},
  );

  bool _answered(int q) => widget.details.questions[q].isSingleChoice
      ? _single[q] != null
      : _multi[q].isNotEmpty;

  void _emit() {
    final all = List.generate(widget.details.questionCount, _answered);
    if (!all.every((a) => a)) {
      widget.onChanged(null);
      return;
    }
    widget.onChanged(
      Survey([
        for (var q = 0; q < widget.details.questionCount; q++)
          if (widget.details.questions[q].isSingleChoice)
            BigInt.from(_single[q]!)
          else
            _multi[q].fold(
              BigInt.zero,
              (mask, bit) => mask | (BigInt.one << bit),
            ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.details.questions[_page];
    final last = _page == widget.details.questionCount - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'QUESTION ${_page + 1} OF ${widget.details.questionCount}',
              style: dbLabel(size: 10),
            ),
            const Spacer(),
            Text(
              q.isSingleChoice ? 'PICK ONE' : 'PICK ANY',
              style: dbLabel(size: 9, color: Db.segnale),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < q.options.length; i++)
          _OptionTile(
            label: q.options[i],
            selected: q.isSingleChoice
                ? _single[_page] == i
                : _multi[_page].contains(i),
            leading: Icon(
              q.isSingleChoice
                  ? (_single[_page] == i
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off)
                  : (_multi[_page].contains(i)
                        ? Icons.check_box
                        : Icons.check_box_outline_blank),
              size: 18,
              color:
                  (q.isSingleChoice
                      ? _single[_page] == i
                      : _multi[_page].contains(i))
                  ? Db.segnale
                  : Db.mute,
            ),
            onTap: () {
              setState(() {
                if (q.isSingleChoice) {
                  _single[_page] = i;
                } else if (!_multi[_page].add(i)) {
                  _multi[_page].remove(i);
                }
              });
              _emit();
            },
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (_page > 0)
              OutlinedButton(
                key: SurveyBallot.previousQuestionKey,
                onPressed: () => setState(() => _page -= 1),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Db.mute,
                  side: const BorderSide(color: Db.rule),
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text('BACK', style: dbMono(11, Db.mute, wght: 700)),
              ),
            const Spacer(),
            if (!last)
              OutlinedButton(
                key: SurveyBallot.nextQuestionKey,
                onPressed: _answered(_page)
                    ? () => setState(() => _page += 1)
                    : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Db.segnale,
                  side: const BorderSide(color: Db.segnale),
                  shape: const RoundedRectangleBorder(),
                ),
                child: Text(
                  'NEXT QUESTION',
                  style: dbMono(11, Db.segnale, wght: 700),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
