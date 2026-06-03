import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tessera/data/services/chain_writer.dart';
import 'package:tessera/data/services/poll_creator.dart';
import 'package:tessera/data/services/wallet_service.dart';
import 'package:tessera/ui/features/create/create_screen.dart';
import 'package:tessera/ui/features/create/survey_question_builder.dart';

/// Records which `create*Poll` the screen calls (and with which options) without
/// touching a chain. [canSign] is parameterized so we can drive the dev-signer
/// gate: true → ranked/quadratic tiles enabled; false → disabled + hinted.
class _FakePollCreator extends PollCreator {
  final bool signs;
  String? calledModule;
  List<String>? calledOptions;
  List<SurveyQuestion>? calledQuestions;

  _FakePollCreator({required this.signs})
      : super(
          writer: ChainWriter(
              rpcUrl: 'http://localhost:0', chainId: 31337, privateKey: ''),
          registryAbiJson: '[]',
          anonAbiJson: '[]',
          approvalAbiJson: '[]',
          surveyVotingAbiJson: '[]',
        );

  @override
  bool get canSign => signs;
  @override
  String? get signer => '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';

  Future<String> _record(String module, List<String> options) async {
    calledModule = module;
    calledOptions = options;
    return '0xfeed';
  }

  @override
  Future<String> createAnonPoll(
          {required String title,
          required String description,
          required List<String> options}) =>
      _record('anon-vote', options);
  @override
  Future<String> createApprovalPoll(
          {required String title,
          required String description,
          required List<String> options}) =>
      _record('approval-vote', options);
  @override
  Future<String> createRankedPoll(
          {required String title,
          required String description,
          required List<String> options}) =>
      _record('ranked-vote', options);
  @override
  Future<String> createQuadraticPoll(
          {required String title,
          required String description,
          required List<String> options}) =>
      _record('quadratic-vote', options);
  @override
  Future<String> createSurveyPoll(
      {required String title,
      required String description,
      required List<SurveyQuestion> questions}) async {
    calledModule = 'survey-vote';
    calledQuestions = questions;
    return '0xfeed';
  }
}

/// The 5-tile picker + form is taller than the default 800×600 test viewport;
/// a ListView culls below-the-fold children offstage, so TextFields/buttons
/// wouldn't be findable. Pumping on a tall surface lays the whole form out
/// onstage. Must run INSIDE the test body (setSurfaceSize asserts `inTest`).
Future<void> _pumpCreate(WidgetTester tester, PollCreator creator) async {
  await tester.binding.setSurfaceSize(const Size(800, 2600));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_wrap(creator));
  await tester.pumpAndSettle();
}

/// Like [_pumpCreate] but on an EXTRA-tall surface — the survey question builder
/// (a card per question + option rows) is much taller than the flat form, so the
/// many-question validation case needs more vertical room to lay out onstage.
Future<void> _pumpCreateTall(WidgetTester tester, PollCreator creator) async {
  await tester.binding.setSurfaceSize(const Size(800, 12000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_wrap(creator));
  await tester.pumpAndSettle();
}

/// `MaterialApp.router` harness with a `/` route so `_deploy`'s success-path
/// `context.go('/')` resolves (a plain MaterialApp would throw `GoRouter.of`).
Widget _wrap(PollCreator creator) {
  final router = GoRouter(
    initialLocation: '/create',
    routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('HOME'))),
      GoRoute(path: '/create', builder: (_, _) => const CreateScreen()),
    ],
  );
  return MultiProvider(
    providers: [
      Provider<PollCreator>.value(value: creator),
      ChangeNotifierProvider<WalletService>(
        create: (_) =>
            WalletService(registryAbiJson: '[]', anonAbiJson: '[]'),
      ),
    ],
    child: MaterialApp.router(routerConfig: router),
  );
}

/// Tap a module tile by its title. The whole form is onstage (tall surface), so
/// no scrolling is needed — tap directly.
Future<void> _selectTile(WidgetTester tester, String title) async {
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// Add option rows until there are [target] of them. Each ADD OPTION tap appends
/// one empty controller; we fill the new rows so the non-empty-options filter
/// keeps them. Starts from the 2 default rows (Yes/No).
Future<void> _growOptionsTo(WidgetTester tester, int target) async {
  for (var i = 2; i < target; i++) {
    await tester.tap(find.text('ADD OPTION'));
    await tester.pumpAndSettle();
  }
  // Fill every option field so trimmed-empty filtering doesn't drop rows.
  final fields = find.byType(TextField);
  // Fields: TITLE, DESCRIPTION, then one per option row.
  for (var i = 0; i < target; i++) {
    await tester.enterText(fields.at(2 + i), 'Opt${i + 1}');
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'picker offers Ranked + Quadratic tiles, ENABLED with the dev-signer',
      (tester) async {
    await _pumpCreate(tester, _FakePollCreator(signs: true));

    expect(find.textContaining('Ranked choice'), findsOneWidget);
    expect(find.textContaining('Quadratic'), findsOneWidget);
    // Canonical module strings surfaced in the enabled subtitles.
    expect(find.textContaining('(ranked-vote)'), findsOneWidget);
    expect(find.textContaining('(quadratic-vote)'), findsOneWidget);
    // Enabled tiles do NOT show the "needs the dev-signer" hint.
    expect(find.textContaining('Needs the dev-signer'), findsNothing);
  });

  testWidgets(
      'without the dev-signer, Ranked + Quadratic are DISABLED and hinted',
      (tester) async {
    await _pumpCreate(tester, _FakePollCreator(signs: false));

    // Both tiles still shown for discoverability…
    expect(find.textContaining('Ranked choice'), findsOneWidget);
    expect(find.textContaining('Quadratic'), findsOneWidget);
    // …but with the dev-signer hint, and tagged with the canonical strings.
    expect(
        find.textContaining('Needs the dev-signer to deploy from mobile. '
            '(ranked-vote)'),
        findsOneWidget);
    expect(
        find.textContaining('Needs the dev-signer to deploy from mobile. '
            '(quadratic-vote)'),
        findsOneWidget);
  });

  testWidgets('selecting Ranked + deploy calls createRankedPoll', (
    tester,
  ) async {
    final creator = _FakePollCreator(signs: true);
    await _pumpCreate(tester, creator);

    await tester.enterText(find.byType(TextField).first, 'My ranked poll');
    await _selectTile(tester, 'Ranked choice — rank your favorites');

    final deploy = find.text('DEPLOY POLL (DEV SIGNER)');
    await tester.tap(deploy);
    await tester.pumpAndSettle();

    expect(creator.calledModule, 'ranked-vote');
    expect(creator.calledOptions, ['Yes', 'No']);
  });

  testWidgets('selecting Quadratic + deploy calls createQuadraticPoll', (
    tester,
  ) async {
    final creator = _FakePollCreator(signs: true);
    await _pumpCreate(tester, creator);

    await tester.enterText(find.byType(TextField).first, 'My QV poll');
    await _selectTile(tester, 'Quadratic — spend 100 credits, cost = votes²');

    final deploy = find.text('DEPLOY POLL (DEV SIGNER)');
    await tester.tap(deploy);
    await tester.pumpAndSettle();

    expect(creator.calledModule, 'quadratic-vote');
    expect(creator.calledOptions, ['Yes', 'No']);
  });

  testWidgets(
      'ranked with 9 options DISABLES deploy + shows the ≤8 hint (no call)',
      (tester) async {
    final creator = _FakePollCreator(signs: true);
    await _pumpCreate(tester, creator);

    await tester.enterText(find.byType(TextField).first, 'Too many');
    await _selectTile(tester, 'Ranked choice — rank your favorites');
    await _growOptionsTo(tester, 9);

    // The 8-option-cap hint is shown…
    expect(find.textContaining('at most 8 options'), findsOneWidget);

    // …and the deploy button is disabled (onPressed == null), so tapping is a
    // no-op: no create* method runs.
    final deploy = find.text('DEPLOY POLL (DEV SIGNER)');
    final button = tester.widget<FilledButton>(
        find.ancestor(of: deploy, matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull, reason: 'submit disabled at 9 options');

    await tester.tap(deploy, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(creator.calledModule, isNull, reason: 'no deploy fired');
  });

  testWidgets('quadratic with 9 options also DISABLES deploy (≤8 guard)', (
    tester,
  ) async {
    final creator = _FakePollCreator(signs: true);
    await _pumpCreate(tester, creator);

    await tester.enterText(find.byType(TextField).first, 'Too many QV');
    await _selectTile(tester, 'Quadratic — spend 100 credits, cost = votes²');
    await _growOptionsTo(tester, 9);

    expect(find.textContaining('at most 8 options'), findsOneWidget);
    final deploy = find.text('DEPLOY POLL (DEV SIGNER)');
    final button = tester.widget<FilledButton>(
        find.ancestor(of: deploy, matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull);
    expect(creator.calledModule, isNull);
  });

  testWidgets('ranked with 8 options is allowed (boundary) → createRankedPoll',
      (tester) async {
    final creator = _FakePollCreator(signs: true);
    await _pumpCreate(tester, creator);

    await tester.enterText(find.byType(TextField).first, 'Eight is fine');
    await _selectTile(tester, 'Ranked choice — rank your favorites');
    await _growOptionsTo(tester, 8);

    // No cap hint at the boundary.
    expect(find.textContaining('at most 8 options'), findsNothing);

    final deploy = find.text('DEPLOY POLL (DEV SIGNER)');
    await tester.tap(deploy);
    await tester.pumpAndSettle();

    expect(creator.calledModule, 'ranked-vote');
    expect(creator.calledOptions!.length, 8);
  });

  // ── Survey (12d M5) ───────────────────────────────────────────────────────

  testWidgets('picker offers the Survey tile, ENABLED with the dev-signer',
      (tester) async {
    await _pumpCreate(tester, _FakePollCreator(signs: true));

    expect(find.textContaining('Survey — multiple questions'), findsOneWidget);
    expect(find.textContaining('(survey-vote)'), findsOneWidget);
    // Enabled → no dev-signer hint on the survey subtitle.
    expect(
        find.textContaining('Needs the dev-signer to deploy from mobile. '
            '(survey-vote)'),
        findsNothing);
  });

  testWidgets('without the dev-signer, the Survey tile is DISABLED + hinted',
      (tester) async {
    await _pumpCreate(tester, _FakePollCreator(signs: false));

    expect(find.textContaining('Survey — multiple questions'), findsOneWidget);
    expect(
        find.textContaining('Needs the dev-signer to deploy from mobile. '
            '(survey-vote)'),
        findsOneWidget);
  });

  testWidgets(
      'selecting Survey swaps the flat OPTIONS list for the question builder',
      (tester) async {
    await _pumpCreate(tester, _FakePollCreator(signs: true));
    await _selectTile(tester, 'Survey — multiple questions');

    // The flat OPTIONS editor + ADD OPTION button are gone; the builder shows a
    // QUESTION 1 card with its own type toggle + ADD QUESTION.
    expect(find.text('QUESTIONS'), findsOneWidget);
    expect(find.text('QUESTION 1'), findsOneWidget);
    expect(find.text('ADD QUESTION'), findsOneWidget);
    expect(find.text('Single choice'), findsOneWidget);
    expect(find.text('Multi-select'), findsOneWidget);
  });

  testWidgets(
      'a survey question with <2 non-empty options keeps deploy DISABLED + hints',
      (tester) async {
    final creator = _FakePollCreator(signs: true);
    await _pumpCreate(tester, creator);

    await tester.enterText(find.byType(TextField).first, 'Survey title');
    await _selectTile(tester, 'Survey — multiple questions');

    // Default question starts with 2 EMPTY option rows → only 0 non-empty.
    // Fill just one of them, leaving the other empty (empty rows are dropped).
    await tester.enterText(find.byKey(const ValueKey('q0-opt0')), 'Only one');
    await tester.pumpAndSettle();

    expect(find.textContaining('needs at least 2 options'), findsOneWidget);
    final deploy = find.text('DEPLOY POLL (DEV SIGNER)');
    final button = tester.widget<FilledButton>(
        find.ancestor(of: deploy, matching: find.byType(FilledButton)));
    expect(button.onPressed, isNull, reason: '1 non-empty option blocks deploy');

    await tester.tap(deploy, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(creator.calledModule, isNull, reason: 'no survey deploy fired');
  });

  testWidgets(
      'a valid survey deploys → createSurveyPoll with the typed questions',
      (tester) async {
    final creator = _FakePollCreator(signs: true);
    await _pumpCreate(tester, creator);

    await tester.enterText(find.byType(TextField).first, 'My survey');
    await _selectTile(tester, 'Survey — multiple questions');

    // Fill the default question's two option rows + flip it to multi-select.
    await tester.enterText(find.byKey(const ValueKey('q0-opt0')), 'Red');
    await tester.enterText(find.byKey(const ValueKey('q0-opt1')), 'Blue');
    await tester.tap(find.text('Multi-select'));
    await tester.pumpAndSettle();

    final deploy = find.text('DEPLOY POLL (DEV SIGNER)');
    final button = tester.widget<FilledButton>(
        find.ancestor(of: deploy, matching: find.byType(FilledButton)));
    expect(button.onPressed, isNotNull, reason: 'valid survey enables deploy');

    await tester.tap(deploy);
    await tester.pumpAndSettle();

    expect(creator.calledModule, 'survey-vote');
    expect(creator.calledQuestions, isNotNull);
    expect(creator.calledQuestions!.length, 1);
    final q = creator.calledQuestions!.single;
    expect(q.qType, SurveyQType.multiSelect, reason: 'type toggle honored');
    expect(q.options, ['Red', 'Blue'], reason: 'trimmed non-empty options');
  });

  testWidgets(
      'survey ADD QUESTION is capped at MAX_QUESTIONS (button disables at 16)',
      (tester) async {
    await _pumpCreateTall(tester, _FakePollCreator(signs: true));
    await _selectTile(tester, 'Survey — multiple questions');

    // Add questions up to the 16 cap; the ADD QUESTION button then disables so
    // the form can't request more questions than `initialize` accepts.
    for (var i = 1; i < kSurveyMaxQuestions; i++) {
      await tester.tap(find.text('ADD QUESTION'));
      await tester.pumpAndSettle();
    }
    expect(find.text('QUESTION $kSurveyMaxQuestions'), findsOneWidget);

    final addBtn = tester.widget<TextButton>(find.ancestor(
        of: find.text('ADD QUESTION'), matching: find.byType(TextButton)));
    expect(addBtn.onPressed, isNull,
        reason: 'ADD QUESTION disabled at the 16-question cap');
  });
}
