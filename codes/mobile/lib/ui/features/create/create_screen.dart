import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/services/poll_creator.dart';
import '../../../data/services/wallet_service.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/theme.dart';
import '../wallet/wallet_button.dart';
import 'survey_question_builder.dart';

/// Create an anon-vote poll from mobile. Signs `PollRegistry.createPoll` through
/// the connected wallet (via [WalletService]). Deploy is gated on a wallet
/// connection; on-chain creation needs a chain the mobile wallet can reach
/// (a public testnet — not the host-local Hardhat node).
class CreateScreen extends StatefulWidget {
  const CreateScreen({super.key});
  @override
  State<CreateScreen> createState() => _CreateScreenState();
}

/// Module type the Create screen can deploy. `anonVote` is the single-choice
/// default; `approvalVote` is the multi-select bitmask module; `rankedVote` is
/// instant-runoff; `quadraticVote` is credit-allocation; `surveyVote` is a
/// multi-question survey (its own question builder, NOT the flat OPTIONS list).
/// `blindVote` is shown for discoverability but DISABLED here — its `initialize`
/// needs a reveal-window param the mobile create flow doesn't collect yet, so
/// deploying it from mobile is web-only (selecting it must never mis-deploy an
/// anon poll).
enum _ModuleType {
  anonVote,
  approvalVote,
  rankedVote,
  quadraticVote,
  surveyVote,
  blindVote,
}

/// On-chain `MAX_OPTIONS` for the ranked + quadratic modules (each packs a
/// per-option nibble into a 32-bit word). The form enforces 2..8 options when
/// either is selected so `initialize` can't revert with `TooManyOptions`.
const int _rankedQuadraticMaxOptions = 8;

class _CreateScreenState extends State<CreateScreen> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  final _options = <TextEditingController>[
    TextEditingController(text: 'Yes'),
    TextEditingController(text: 'No'),
  ];
  // The multi-question survey draft — only used when `surveyVote` is selected.
  // Owns its own per-question option controllers (NOT the flat `_options`).
  final _survey = SurveyDraft();
  _ModuleType _module = _ModuleType.anonVote;
  bool _busy = false;

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    for (final c in _options) {
      c.dispose();
    }
    _survey.dispose();
    super.dispose();
  }

  /// Whether the multi-question survey builder is the active form (its own
  /// 1..16-questions / 2..32-options-per-question validation replaces the flat
  /// OPTIONS editor + the ranked/quadratic 2..8 guard).
  bool get _isSurvey => _module == _ModuleType.surveyVote;

  /// Ranked + quadratic cap options at 8 on-chain; everything else allows the
  /// module's own (higher) cap, so only the row count matters here.
  bool get _moduleCapsAtEight =>
      _module == _ModuleType.rankedVote ||
      _module == _ModuleType.quadraticVote;

  /// True when the current option-row count is valid for the selected module.
  /// Ranked/quadratic require 2..8; anon/approval require ≥2 (no upper bound the
  /// form needs to police). Reactive off `_options.length`, which only changes
  /// via add/remove-row `setState` — exactly when the submit gate should update.
  bool get _optionCountOk {
    final n = _options.length;
    if (n < 2) return false;
    if (_moduleCapsAtEight && n > _rankedQuadraticMaxOptions) return false;
    return true;
  }

  Future<void> _deploy(WalletService w) async {
    final creator = context.read<PollCreator>();
    final title = _title.text.trim();
    // Survey is its OWN deploy path — it doesn't use the flat `_options` list, so
    // it must branch BEFORE the `opts.length < 2` guard below (which would
    // otherwise block a perfectly valid survey). Survey is dev-signer-only: its
    // tile is disabled without the dev-signer, so the wallet path never reaches
    // here — keeping the wallet path anon-only (no anon mis-deploy).
    if (_isSurvey) {
      await _deploySurvey(creator, title);
      return;
    }
    final opts =
        _options.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList();
    if (title.isEmpty || opts.length < 2) {
      _snack('Add a title and at least two options.');
      return;
    }
    // Guard the ranked/quadratic 8-option cap before signing so the on-chain
    // `initialize` can't revert with `TooManyOptions`. (The submit button is also
    // disabled in this state; this is the belt-and-braces check.)
    if (_moduleCapsAtEight && opts.length > _rankedQuadraticMaxOptions) {
      _snack('Ranked & quadratic polls allow at most '
          '$_rankedQuadraticMaxOptions options.');
      return;
    }
    setState(() => _busy = true);
    try {
      // Dev-signer (DEV_PRIVATE_KEY) bypasses wallet connection for local dev.
      // Module dispatch is an explicit switch so an unhandled type can NEVER
      // silently fall through to an anon deploy — each enabled module maps to its
      // own creator call, and only anonVote reaches createAnonPoll. (Blind is
      // disabled in the picker so it can't reach here.)
      final String tx;
      if (creator.canSign) {
        final title0 = title;
        final desc0 = _desc.text.trim();
        switch (_module) {
          case _ModuleType.approvalVote:
            tx = await creator.createApprovalPoll(
                title: title0, description: desc0, options: opts);
          case _ModuleType.rankedVote:
            tx = await creator.createRankedPoll(
                title: title0, description: desc0, options: opts);
          case _ModuleType.quadraticVote:
            tx = await creator.createQuadraticPoll(
                title: title0, description: desc0, options: opts);
          case _ModuleType.surveyVote:
            // Unreachable: `_isSurvey` returns early into `_deploySurvey` above.
            // Listed only for switch exhaustiveness; never deploys via `opts`.
            return;
          case _ModuleType.anonVote:
          case _ModuleType.blindVote:
            tx = await creator.createAnonPoll(
                title: title0, description: desc0, options: opts);
        }
      } else {
        // The wallet path only deploys anon-vote today; approval/ranked/quadratic
        // over the wallet path are a follow-up (the dev-signer is the supported
        // path for those). Their tiles are disabled without the dev-signer, so a
        // wallet user can only ever select anon here — no anon mis-deploy.
        tx = await w.createPoll(
            title: title, description: _desc.text.trim(), options: opts);
      }
      if (!mounted) return;
      _snack('Deploy sent · ${shortAddr(tx)}');
      context.canPop() ? context.pop() : context.go('/');
    } catch (e) {
      if (mounted) _snack('Deploy failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Deploy the multi-question survey via the dev-signer. Validates the draft's
  /// own 1..16-questions / 2..32-options-per-question caps (the contract's
  /// `MAX_QUESTIONS` / `MAX_OPTIONS`) before signing — the flat option-count
  /// guard does NOT apply to surveys.
  Future<void> _deploySurvey(PollCreator creator, String title) async {
    if (title.isEmpty) {
      _snack('Add a title.');
      return;
    }
    final err = _survey.validationError;
    if (err != null) {
      _snack(err);
      return;
    }
    setState(() => _busy = true);
    try {
      final tx = await creator.createSurveyPoll(
        title: title,
        description: _desc.text.trim(),
        questions: _survey.toQuestions(),
      );
      if (!mounted) return;
      _snack('Deploy sent · ${shortAddr(tx)}');
      context.canPop() ? context.pop() : context.go('/');
    } catch (e) {
      if (mounted) _snack('Deploy failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: dbMono(12, Db.chalk)),
        backgroundColor: Db.slate,
      ));

  @override
  Widget build(BuildContext context) {
    final w = context.watch<WalletService>();
    final devSigner = context.read<PollCreator>().canSign;
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('CREATE', style: dbHero(48)),
                  const SizedBox(height: 10),
                  Text(
                    'Deploy an anonymous poll — pick the voting type, then sign.',
                    style: dbSans(13, 400, Db.chalkDim, height: 1.5),
                  ),
                  const SizedBox(height: 20),
                  _walletBanner(w, devSigner),
                  const SizedBox(height: 22),
                  Text('VOTING TYPE', style: dbLabel(size: 10, tracking: 0.16)),
                  const SizedBox(height: 10),
                  _modulePicker(devSigner),
                  const SizedBox(height: 22),
                  _field('TITLE', _title, 'Adopt the new logo?'),
                  const SizedBox(height: 16),
                  _field('DESCRIPTION', _desc, 'Optional context', maxLines: 3),
                  const SizedBox(height: 20),
                  if (_isSurvey) ...[
                    Text('QUESTIONS',
                        style: dbLabel(size: 10, tracking: 0.16)),
                    const SizedBox(height: 10),
                    SurveyQuestionBuilder(
                      draft: _survey,
                      onChanged: () => setState(() {}),
                    ),
                    if (_survey.validationError != null) ...[
                      const SizedBox(height: 10),
                      _surveyHint(_survey.validationError!),
                    ],
                  ] else ...[
                    Text('OPTIONS', style: dbLabel(size: 10, tracking: 0.16)),
                    const SizedBox(height: 10),
                    for (var i = 0; i < _options.length; i++) _optionRow(i),
                    const SizedBox(height: 6),
                    _addOptionButton(),
                    if (_moduleCapsAtEight && !_optionCountOk) ...[
                      const SizedBox(height: 8),
                      _optionLimitHint(),
                    ],
                  ],
                  const SizedBox(height: 28),
                  _deployButton(w, devSigner),
                  const SizedBox(height: 14),
                  Text(
                    devSigner
                        ? 'Dev signer active (DEV_PRIVATE_KEY) — deploys are '
                            'signed locally and broadcast straight to the '
                            'configured RPC. No wallet needed.'
                        : 'Creating a poll signs an on-chain transaction. A phone '
                            'wallet can only broadcast to a chain it can reach — '
                            'use a public testnet, not the host-local Hardhat node.',
                    style: dbMono(10, Db.muteDim, height: 1.6),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Module-type picker: anon (default) / approval / ranked / quadratic / blind.
  // Approval deploys the multi-select bitmask module; ranked is instant-runoff;
  // quadratic is credit-allocation (each is the canonical module string Browse
  // uses to dispatch the matching screen). Blind is shown but disabled — see
  // [_ModuleType]. Approval/ranked/quadratic create all need the dev-signer (the
  // wallet path is anon-only today), so when [devSigner] is false those tiles are
  // disabled with a hint — which also keeps the wallet path anon-only (a wallet
  // user can never select them, so no anon mis-deploy).
  Widget _modulePicker(bool devSigner) {
    final tiles = <Widget>[
      _moduleTile(
        type: _ModuleType.anonVote,
        title: 'Anonymous — single choice',
        subtitle: 'Pick exactly one option. (anon-vote)',
        icon: Icons.radio_button_checked,
        accent: Db.segnale,
        enabled: true,
      ),
      _moduleTile(
        type: _ModuleType.approvalVote,
        title: 'Approval — multi-select',
        subtitle: devSigner
            ? 'Approve any number of options; the tally counts every approval. '
                '(approval-vote)'
            : 'Needs the dev-signer to deploy from mobile. (approval-vote)',
        icon: Icons.check_box,
        accent: Db.oltremare,
        enabled: devSigner,
      ),
      _moduleTile(
        type: _ModuleType.rankedVote,
        title: 'Ranked choice — rank your favorites',
        subtitle: devSigner
            ? 'Rank options; an instant-runoff finds the winner. Up to 8 options. '
                '(ranked-vote)'
            : 'Needs the dev-signer to deploy from mobile. (ranked-vote)',
        icon: Icons.format_list_numbered,
        accent: Db.success,
        enabled: devSigner,
      ),
      _moduleTile(
        type: _ModuleType.quadraticVote,
        title: 'Quadratic — spend 100 credits, cost = votes²',
        subtitle: devSigner
            ? 'Allocate a credit budget across options; cost grows as votes². '
                'Up to 8 options. (quadratic-vote)'
            : 'Needs the dev-signer to deploy from mobile. (quadratic-vote)',
        icon: Icons.calculate_outlined,
        accent: Db.catSocial,
        enabled: devSigner,
      ),
      _moduleTile(
        type: _ModuleType.surveyVote,
        title: 'Survey — multiple questions',
        subtitle: devSigner
            ? 'Compose several questions (single-choice or multi-select); voters '
                'answer them all in one ballot. (survey-vote)'
            : 'Needs the dev-signer to deploy from mobile. (survey-vote)',
        icon: Icons.list_alt,
        accent: Db.oltremare,
        enabled: devSigner,
      ),
      _moduleTile(
        type: _ModuleType.blindVote,
        title: 'Blind — commit-reveal',
        subtitle: 'Create on the web app (needs a reveal window). (blind-vote)',
        icon: Icons.lock_clock,
        accent: Db.amber,
        enabled: false,
      ),
    ];
    return Column(children: [
      for (var i = 0; i < tiles.length; i++) ...[
        if (i > 0) const SizedBox(height: 8),
        tiles[i],
      ],
    ]);
  }

  Widget _moduleTile({
    required _ModuleType type,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required bool enabled,
  }) {
    final selected = _module == type && enabled;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: InkWell(
        onTap: enabled ? () => setState(() => _module = type) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.10) : Db.slate3,
            border: Border.all(
                color: selected ? accent : Db.rule, width: selected ? 2 : 1),
          ),
          child: Row(children: [
            Icon(icon, size: 18, color: selected ? accent : Db.mute),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: dbSans(14, 700, Db.chalk)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: dbMono(10, Db.mute, height: 1.4)),
                ],
              ),
            ),
            if (!enabled)
              const Icon(Icons.lock_outline, size: 14, color: Db.muteDim)
            else
              Icon(
                  selected
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: selected ? accent : Db.muteDim),
          ]),
        ),
      ),
    );
  }

  Widget _walletBanner(WalletService w, bool devSigner) {
    if (devSigner) {
      final addr = context.read<PollCreator>().signer ?? '';
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: const BoxDecoration(
          color: Db.slate,
          border: Border(left: BorderSide(color: Db.success, width: 3)),
        ),
        child: Row(children: [
          const Icon(Icons.vpn_key_outlined, size: 18, color: Db.success),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Dev signer active\n$addr',
                style: dbMono(11, Db.chalkDim, height: 1.5)),
          ),
        ]),
      );
    }
    final connected = w.isConnected;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Db.slate,
        border: Border(
            left: BorderSide(
                color: connected ? Db.success : Db.segnale, width: 3)),
      ),
      // Not-connected shows a wide "SET WC_PROJECT_ID" hint button; stacking it
      // BELOW the prompt (instead of in the same Row) avoids a right-overflow on
      // narrow phones where the button + Expanded text can't share one line.
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Icon(
                connected
                    ? Icons.check_circle_outline
                    : Icons.account_balance_wallet_outlined,
                size: 18,
                color: connected ? Db.success : Db.segnale),
            const SizedBox(width: 12),
            Expanded(
              child: connected
                  ? Text('Wallet connected\n${w.address ?? ''}',
                      style: dbMono(11, Db.chalkDim, height: 1.5))
                  : Text('Connect a wallet to deploy',
                      style: dbSans(13, 600, Db.chalk)),
            ),
          ]),
          if (!connected) ...[
            const SizedBox(height: 12),
            const Align(
                alignment: Alignment.centerLeft, child: WalletButton()),
          ],
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController c, String hint,
          {int maxLines = 1}) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: dbLabel(size: 10, tracking: 0.16)),
        const SizedBox(height: 8),
        TextField(
          controller: c,
          maxLines: maxLines,
          style: dbSans(15, 600, Db.chalk),
          cursorColor: Db.segnale,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Db.slate3,
            hintText: hint,
            hintStyle: dbSans(14, 400, Db.muteDim),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.rule)),
            focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.segnale)),
          ),
        ),
      ]);

  Widget _optionRow(int i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Text('0${i + 1}', style: dbMono(13, Db.mute, wght: 700)),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _options[i],
              style: dbSans(14, 600, Db.chalk),
              cursorColor: Db.segnale,
              decoration: InputDecoration(
                isDense: true,
                filled: true,
                fillColor: Db.slate3,
                hintText: 'Option ${i + 1}',
                hintStyle: dbSans(13, 400, Db.muteDim),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                enabledBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Db.rule)),
                focusedBorder: const OutlineInputBorder(
                    borderRadius: BorderRadius.zero,
                    borderSide: BorderSide(color: Db.segnale)),
              ),
            ),
          ),
          if (_options.length > 2)
            IconButton(
              icon: const Icon(Icons.close, size: 16, color: Db.mute),
              onPressed: () => setState(() => _options.removeAt(i).dispose()),
            ),
        ]),
      );

  Widget _addOptionButton() => Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () =>
              setState(() => _options.add(TextEditingController())),
          icon: const Icon(Icons.add, size: 15, color: Db.chalkDim),
          label:
              Text('ADD OPTION', style: dbLabel(size: 11, color: Db.chalkDim)),
        ),
      );

  // Shown only for ranked/quadratic when the option-row count is out of the 2..8
  // range the on-chain `initialize` accepts (so the user can see WHY submit is
  // disabled instead of hitting a `TooManyOptions` revert).
  Widget _optionLimitHint() {
    final n = _options.length;
    final msg = n > _rankedQuadraticMaxOptions
        ? 'Ranked & quadratic polls allow at most '
            '$_rankedQuadraticMaxOptions options — remove ${n - _rankedQuadraticMaxOptions}.'
        : 'Add at least 2 options.';
    return Row(children: [
      const Icon(Icons.info_outline, size: 13, color: Db.amber),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: dbMono(10, Db.amber, height: 1.5))),
    ]);
  }

  // The survey's own validation hint (1..16 questions / 2..32 options each),
  // surfaced so the user sees WHY deploy is disabled before an `initialize`
  // revert. Distinct from the flat-options `_optionLimitHint`.
  Widget _surveyHint(String msg) => Row(children: [
        const Icon(Icons.info_outline, size: 13, color: Db.amber),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: dbMono(10, Db.amber, height: 1.5))),
      ]);

  Widget _deployButton(WalletService w, bool devSigner) {
    final canDeploy = devSigner || w.isConnected;
    // Survey gates on its OWN validity (1..16 questions / 2..32 options each);
    // every other module gates on the flat option-row count.
    final formOk = _isSurvey ? _survey.isValid : _optionCountOk;
    final enabled = canDeploy && !_busy && formOk;
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        onPressed: enabled ? () => _deploy(w) : null,
        style: FilledButton.styleFrom(
          backgroundColor: Db.segnale,
          disabledBackgroundColor: Db.slate,
          foregroundColor: Db.chalk,
          shape: const RoundedRectangleBorder(),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
        child: Text(
          _busy
              ? 'DEPLOYING…'
              : (devSigner
                  ? 'DEPLOY POLL (DEV SIGNER)'
                  : (w.isConnected ? 'DEPLOY POLL' : 'CONNECT WALLET FIRST')),
          style: dbSans(13, 800, canDeploy ? Db.chalk : Db.mute,
              letterSpacing: 1.4),
        ),
      ),
    );
  }
}
