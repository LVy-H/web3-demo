import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../data/services/created_polls_store.dart';
import '../../../data/services/poll_creator.dart';
import '../../../data/services/relay_client.dart' show CreatePollResult;
import '../../../data/services/sponsored_poll_creator.dart';
import '../../../data/services/wallet_service.dart';
import '../../core/dot_grid_background.dart';
import '../../core/format.dart';
import '../../core/signing_explainer.dart';
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
  // Whether wallet-free sponsored creation is reachable (the relayer answered
  // /info). Probed once on open; gates the module picker + the signing banner.
  bool _sponsoredReady = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final info = await context.read<SponsoredPollCreator>().probe();
      // Sponsored create needs the relayer to know the registry; if `/info`
      // reports `registry: null` the create endpoint 503s, so don't offer it.
      if (mounted) {
        setState(() => _sponsoredReady = info != null && info.registry != null);
      }
    });
  }

  /// Any wallet-free create path available: the local dev-signer OR the
  /// sponsored relayer. The richer module types (approval/ranked/quadratic/
  /// survey) are enabled whenever EITHER is — no wallet required.
  bool _walletFree(bool devSigner) => devSigner || _sponsoredReady;

  /// Canonical module-type string for the sponsored `createPoll` call.
  String _moduleString(_ModuleType m) => switch (m) {
    _ModuleType.anonVote => 'anon-vote',
    _ModuleType.approvalVote => 'approval-vote',
    _ModuleType.rankedVote => 'ranked-vote',
    _ModuleType.quadraticVote => 'quadratic-vote',
    _ModuleType.surveyVote => 'survey-vote',
    _ModuleType.blindVote => 'blind-vote', // never deployed here
  };

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
      _module == _ModuleType.rankedVote || _module == _ModuleType.quadraticVote;

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
    final opts = _options
        .map((c) => c.text.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (title.isEmpty || opts.length < 2) {
      _snack('Add a title and at least two options.');
      return;
    }
    // Guard the ranked/quadratic 8-option cap before signing so the on-chain
    // `initialize` can't revert with `TooManyOptions`. (The submit button is also
    // disabled in this state; this is the belt-and-braces check.)
    if (_moduleCapsAtEight && opts.length > _rankedQuadraticMaxOptions) {
      _snack(
        'Ranked & quadratic polls allow at most '
        '$_rankedQuadraticMaxOptions options.',
      );
      return;
    }
    setState(() => _busy = true);
    final desc0 = _desc.text.trim();
    try {
      // Signing priority: local dev-signer → wallet-free sponsored relayer →
      // (fenced) connected wallet → guidance. The explicit switch means an
      // unhandled type can NEVER silently fall through to an anon deploy.
      if (creator.canSign) {
        final String tx;
        switch (_module) {
          case _ModuleType.approvalVote:
            tx = await creator.createApprovalPoll(
              title: title,
              description: desc0,
              options: opts,
            );
          case _ModuleType.rankedVote:
            tx = await creator.createRankedPoll(
              title: title,
              description: desc0,
              options: opts,
            );
          case _ModuleType.quadraticVote:
            tx = await creator.createQuadraticPoll(
              title: title,
              description: desc0,
              options: opts,
            );
          case _ModuleType.surveyVote:
            return; // unreachable: survey branched into _deploySurvey above
          case _ModuleType.anonVote:
          case _ModuleType.blindVote:
            tx = await creator.createAnonPoll(
              title: title,
              description: desc0,
              options: opts,
            );
        }
        if (!mounted) return;
        _snack('Deploy sent · ${shortAddr(tx)}');
        context.canPop() ? context.pop() : context.go('/');
      } else if (_sponsoredReady) {
        // Wallet-free: the relayer pays gas + owns the poll. Works for every
        // sponsored module (anon/approval/ranked/quadratic), not just anon.
        final res = await context.read<SponsoredPollCreator>().createFlatPoll(
          moduleType: _moduleString(_module),
          title: title,
          description: desc0,
          options: opts,
        );
        _afterSponsored(res);
      } else if (w.isConnected) {
        // Advanced/fenced wallet path (anon-only, public-testnet — pending P10).
        final tx = await w.createPoll(
          title: title,
          description: desc0,
          options: opts,
        );
        if (!mounted) return;
        _snack('Deploy sent · ${shortAddr(tx)}');
        context.canPop() ? context.pop() : context.go('/');
      } else {
        _snack(
          'No signer available — start the relayer (./dev-stack.sh up) for '
          'sponsored creation, or set DEV_PRIVATE_KEY for local dev.',
        );
      }
    } catch (e) {
      if (mounted) _snack('Deploy failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Handle a sponsored-create result: navigate straight to the new poll on
  /// success, or surface the relayer's message.
  void _afterSponsored(CreatePollResult res) {
    if (!mounted) return;
    if (res.ok) {
      // Remember it locally so the browse "MINE" filter can surface it (the
      // on-chain creator is the relayer, so this is the only "I made it" signal).
      context.read<CreatedPollsStore>().add(res.pollAddress!);
      _snack('Poll created · ${shortAddr(res.pollAddress!)}');
      context.go('/poll/${res.pollAddress}?module=${_moduleString(_module)}');
    } else {
      _snack(res.error ?? 'Could not create the poll.');
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
    final desc0 = _desc.text.trim();
    try {
      if (creator.canSign) {
        final tx = await creator.createSurveyPoll(
          title: title,
          description: desc0,
          questions: _survey.toQuestions(),
        );
        if (!mounted) return;
        _snack('Deploy sent · ${shortAddr(tx)}');
        context.canPop() ? context.pop() : context.go('/');
      } else if (_sponsoredReady) {
        final res = await context.read<SponsoredPollCreator>().createSurveyPoll(
          title: title,
          description: desc0,
          questions: _survey.toQuestions(),
        );
        _afterSponsored(res);
      } else {
        _snack(
          'No signer available — start the relayer (./dev-stack.sh up) for '
          'sponsored creation, or set DEV_PRIVATE_KEY for local dev.',
        );
      }
    } catch (e) {
      if (mounted) _snack('Deploy failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(m, style: dbMono(12, Db.chalk)),
      backgroundColor: Db.slate,
    ),
  );

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
                  _modulePicker(_walletFree(devSigner)),
                  const SizedBox(height: 22),
                  _field('TITLE', _title, 'Adopt the new logo?'),
                  const SizedBox(height: 16),
                  _field('DESCRIPTION', _desc, 'Optional context', maxLines: 3),
                  const SizedBox(height: 20),
                  if (_isSurvey) ...[
                    Text('QUESTIONS', style: dbLabel(size: 10, tracking: 0.16)),
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
                        ? 'Signing locally with the dev key — no wallet needed.'
                        : _sponsoredReady
                        ? 'Wallet-free: the relayer sponsors creation (pays '
                              'the gas and runs the poll). No wallet needed.'
                        : 'No signer yet — start the relayer (./dev-stack.sh '
                              'up) for sponsored, wallet-free creation, or set '
                              'DEV_PRIVATE_KEY for local dev. Connecting a '
                              'wallet is an optional advanced path (public '
                              'testnet — pending Phase 10).',
                    style: dbMono(10, Db.muteDim, height: 1.6),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () => showSigningExplainerSheet(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          'How signing works  ›',
                          style: dbLabel(size: 10, color: Db.segnale),
                        ),
                      ),
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
            : 'Needs a signer — start the relayer or set DEV_PRIVATE_KEY. (approval-vote)',
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
            : 'Needs a signer — start the relayer or set DEV_PRIVATE_KEY. (ranked-vote)',
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
            : 'Needs a signer — start the relayer or set DEV_PRIVATE_KEY. (quadratic-vote)',
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
            : 'Needs a signer — start the relayer or set DEV_PRIVATE_KEY. (survey-vote)',
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
    return Column(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          tiles[i],
        ],
      ],
    );
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
              color: selected ? accent : Db.rule,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
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
                  selected ? Icons.check_circle : Icons.radio_button_unchecked,
                  size: 16,
                  color: selected ? accent : Db.muteDim,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// The signing banner — leads with the active **wallet-free** path. Tessera is
  /// wallet-free by design: local dev signs with the dev key, production signs
  /// via the sponsored relayer. The wallet is an optional, fenced advanced path.
  Widget _walletBanner(WalletService w, bool devSigner) {
    // Path 1 — local dev-signer (wallet-free).
    if (devSigner) {
      final addr = context.read<PollCreator>().signer ?? '';
      return _bannerBox(
        accent: Db.success,
        icon: Icons.vpn_key_outlined,
        child: Text(
          'Signing locally (dev signer) — no wallet needed\n$addr',
          style: dbMono(11, Db.chalkDim, height: 1.5),
        ),
      );
    }
    // Path 2 — sponsored relayer (wallet-free, the production default).
    if (_sponsoredReady) {
      return _bannerBox(
        accent: Db.success,
        icon: Icons.bolt_outlined,
        child: Text(
          'Wallet-free — Tessera sponsors creation: the relayer pays the gas '
          'and runs the poll. No wallet needed.',
          style: dbMono(11, Db.chalkDim, height: 1.5),
        ),
      );
    }
    // Path 3 — nothing wallet-free reachable: honest guidance + the optional,
    // fenced "advanced" wallet (public testnet, pending Phase 10).
    final connected = w.isConnected;
    return _bannerBox(
      accent: connected ? Db.success : Db.segnale,
      icon: connected
          ? Icons.check_circle_outline
          : Icons.account_balance_wallet_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          connected
              ? Text(
                  'Wallet connected (advanced)\n${w.address ?? ''}',
                  style: dbMono(11, Db.chalkDim, height: 1.5),
                )
              : Text(
                  'No wallet-free signer reachable. Start the relayer '
                  '(./dev-stack.sh up) for sponsored creation, or set '
                  'DEV_PRIVATE_KEY for local dev.',
                  style: dbSans(12, 500, Db.chalk, height: 1.4),
                ),
          if (w.supported && !connected) ...[
            const SizedBox(height: 12),
            Text(
              'Advanced — public testnet (pending Phase 10)',
              style: dbLabel(size: 9, color: Db.mute),
            ),
            const SizedBox(height: 6),
            const Align(alignment: Alignment.centerLeft, child: WalletButton()),
          ],
        ],
      ),
    );
  }

  /// Shared left-accent banner box for the three signing states.
  Widget _bannerBox({
    required Color accent,
    required IconData icon,
    required Widget child,
  }) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Db.slate,
      border: Border(left: BorderSide(color: accent, width: 3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: accent),
        const SizedBox(width: 12),
        Expanded(child: child),
      ],
    ),
  );

  Widget _field(
    String label,
    TextEditingController c,
    String hint, {
    int maxLines = 1,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
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
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Db.rule),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Db.segnale),
          ),
        ),
      ),
    ],
  );

  Widget _optionRow(int i) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 12,
              ),
              enabledBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.rule),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.segnale),
              ),
            ),
          ),
        ),
        if (_options.length > 2)
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Db.mute),
            onPressed: () => setState(() => _options.removeAt(i).dispose()),
          ),
      ],
    ),
  );

  Widget _addOptionButton() => Align(
    alignment: Alignment.centerLeft,
    child: TextButton.icon(
      onPressed: () => setState(() => _options.add(TextEditingController())),
      icon: const Icon(Icons.add, size: 15, color: Db.chalkDim),
      label: Text('ADD OPTION', style: dbLabel(size: 11, color: Db.chalkDim)),
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
    return Row(
      children: [
        const Icon(Icons.info_outline, size: 13, color: Db.amber),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: dbMono(10, Db.amber, height: 1.5))),
      ],
    );
  }

  // The survey's own validation hint (1..16 questions / 2..32 options each),
  // surfaced so the user sees WHY deploy is disabled before an `initialize`
  // revert. Distinct from the flat-options `_optionLimitHint`.
  Widget _surveyHint(String msg) => Row(
    children: [
      const Icon(Icons.info_outline, size: 13, color: Db.amber),
      const SizedBox(width: 8),
      Expanded(child: Text(msg, style: dbMono(10, Db.amber, height: 1.5))),
    ],
  );

  Widget _deployButton(WalletService w, bool devSigner) {
    // Wallet-free first: any of dev-signer / sponsored relayer / connected wallet
    // can deploy. (No more "connect a wallet" dead-end when the relayer is up.)
    final canDeploy = devSigner || _sponsoredReady || w.isConnected;
    // Survey gates on its OWN validity (1..16 questions / 2..32 options each);
    // every other module gates on the flat option-row count.
    final formOk = _isSurvey ? _survey.isValid : _optionCountOk;
    final enabled = canDeploy && !_busy && formOk;
    final label = _busy
        ? 'DEPLOYING…'
        : devSigner
        ? 'DEPLOY POLL (DEV SIGNER)'
        : _sponsoredReady
        ? 'CREATE POLL — WALLET-FREE'
        : w.isConnected
        ? 'DEPLOY POLL (WALLET)'
        : 'NO SIGNER — START THE RELAYER';
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
          label,
          style: dbSans(
            13,
            800,
            canDeploy ? Db.chalk : Db.mute,
            letterSpacing: 1.4,
          ),
        ),
      ),
    );
  }
}
