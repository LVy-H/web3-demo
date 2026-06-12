// The CREATE flow against the REAL RelayOrganizerPort over faked wire
// dependencies, so the spec §5 privacy contract is pinned end-to-end:
// untouched toggles must reach the sponsored relayer's create-poll JSON as
// visibility=0 / resultsPolicy=0 (the private defaults), the opt-ins as 1/1,
// and a device with no create path must show the deploy button disabled
// with the honest reason — never a dead tap.
import 'package:core_chain/chain_reader.dart';
import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/organizer_journey.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/created_polls_store.dart';
import 'package:feature_join/feature_join.dart' show shareLinkForPoll;
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ── faked wire dependencies ──────────────────────────────────────────────

const _relayerAddress = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _pollAddress = '0x5FbDB2315678afecb367f032d93F642f64180aa3';

/// Minimal flat-module ABI: just `initialize(address,address,string[])` —
/// the only function the deploy encoder touches.
const _flatAbi =
    '[{"type":"function","name":"initialize","stateMutability":"nonpayable",'
    '"inputs":[{"name":"semaphore","type":"address"},'
    '{"name":"_owner","type":"address"},'
    '{"name":"options","type":"string[]"}],"outputs":[]}]';

class _FakeRelay implements RelayClient {
  @override
  Future<RelayerInfo?> getRelayerInfo() async =>
      const RelayerInfo(relayer: _relayerAddress);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('RelayClient.${invocation.memberName}');
}

class _FakeReader implements ChainReader {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('ChainReader.${invocation.memberName}');
}

/// Captures exactly what would go onto the relayer's create-poll wire.
class _CapturingGateway implements OrganizeRelayGateway {
  String? moduleType;
  String? title;
  String? initDataHex;
  int? visibility;
  int? resultsPolicy;
  int createCalls = 0;

  @override
  Future<CreatePollResult> createPoll({
    required String moduleType,
    required String title,
    required String description,
    required String initDataHex,
    required int visibility,
    required int resultsPolicy,
  }) async {
    createCalls++;
    this.moduleType = moduleType;
    this.title = title;
    this.initDataHex = initDataHex;
    this.visibility = visibility;
    this.resultsPolicy = resultsPolicy;
    return const CreatePollResult(pollAddress: _pollAddress);
  }

  @override
  Future<void> startVoting(String pollAddress) async {}

  @override
  Future<void> endVoting(String pollAddress) async {}
}

const Capabilities _sponsoredOnly = Capabilities(
  canProve: false,
  canSign: false,
  canScanQr: false,
  hasNfc: false,
  hasBle: false,
  canUseWallet: false,
  relayerAvailable: true,
);

(_CapturingGateway, RelayOrganizerPort) _port() {
  final gateway = _CapturingGateway();
  final port = RelayOrganizerPort(
    relay: _FakeRelay(),
    reader: _FakeReader(),
    gateway: gateway,
    createdPolls: InMemoryCreatedPollsStore(),
    flatModuleAbiJson: _flatAbi,
    surveyVotingAbiJson: _flatAbi,
  );
  return (gateway, port);
}

Future<void> _pump(
  WidgetTester tester, {
  required OrganizerJourneyPort port,
  Capabilities capabilities = _sponsoredOnly,
}) async {
  // Tall surface: the whole form fits, no scroll choreography in tests.
  tester.view.physicalSize = const Size(800, 2600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: CreateFlowView(
        port: port,
        capabilities: capabilities,
        onDone: (_) {},
      ),
    ),
  );
}

Future<void> _fillMinimalForm(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(CreateFlowView.titleFieldKey),
    'Snack budget',
  );
  await tester.enterText(find.byKey(const Key('create-option-0')), 'Fruit');
  await tester.enterText(find.byKey(const Key('create-option-1')), 'Crisps');
  await tester.pump();
}

void main() {
  testWidgets('untouched form deploys PRIVATE: toggles start OFF and reach '
      'the relayer wire as visibility=0 / resultsPolicy=0', (tester) async {
    final (gateway, port) = _port();
    await _pump(tester, port: port);

    // Both §5 opt-ins render OFF before anyone touches anything.
    expect(
      tester
          .widget<Switch>(find.byKey(CreateFlowView.listedToggleKey))
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<Switch>(find.byKey(CreateFlowView.liveResultsToggleKey))
          .value,
      isFalse,
    );

    await _fillMinimalForm(tester);
    await tester.tap(find.byKey(CreateFlowView.deployButtonKey));
    await tester.pumpAndSettle();

    expect(gateway.createCalls, 1);
    expect(gateway.visibility, 0, reason: 'unlisted is the wire default');
    expect(gateway.resultsPolicy, 0, reason: 'sealed-until-close default');
    expect(gateway.moduleType, 'anon-vote');
    expect(gateway.title, 'Snack budget');
    expect(
      gateway.initDataHex,
      startsWith('0x'),
      reason: 'pre-R4 initialize calldata travels untouched',
    );

    // Post-deploy: the created card with DISTRIBUTE as THE next action.
    expect(find.text('YOUR POLL IS READY'), findsOneWidget);
    expect(find.text('DISTRIBUTE'), findsOneWidget);
  });

  testWidgets('both opt-ins ON reach the wire as visibility=1 / '
      'resultsPolicy=1', (tester) async {
    final (gateway, port) = _port();
    await _pump(tester, port: port);
    await _fillMinimalForm(tester);

    await tester.tap(find.byKey(CreateFlowView.listedToggleKey));
    await tester.tap(find.byKey(CreateFlowView.liveResultsToggleKey));
    await tester.pump();
    await tester.tap(find.byKey(CreateFlowView.deployButtonKey));
    await tester.pumpAndSettle();

    expect(gateway.visibility, 1);
    expect(gateway.resultsPolicy, 1);
  });

  testWidgets('no signer path: deploy is disabled with the honest reason, '
      'and nothing is sent', (tester) async {
    final (gateway, port) = _port();
    await _pump(tester, port: port, capabilities: Capabilities.none);
    await _fillMinimalForm(tester);

    final button = tester.widget<FilledButton>(
      find.byKey(CreateFlowView.deployButtonKey),
    );
    expect(button.onPressed, isNull);
    expect(
      find.byKey(CreateFlowView.disabledReasonKey),
      findsOneWidget,
    );
    expect(
      find.textContaining('needs the sponsoring service or a signing key'),
      findsOneWidget,
      reason: 'spec §3: no bare disabled surface, ever',
    );
    expect(gateway.createCalls, 0);
  });

  testWidgets('an incomplete draft says what is missing instead of '
      'silently refusing', (tester) async {
    final (_, port) = _port();
    await _pump(tester, port: port);

    final button = tester.widget<FilledButton>(
      find.byKey(CreateFlowView.deployButtonKey),
    );
    expect(button.onPressed, isNull);
    expect(
      find.textContaining('Add a title and at least two answer options'),
      findsOneWidget,
    );
  });

  testWidgets('created → DISTRIBUTE opens the share sheet on '
      "feature_join's canonical link for the new poll", (tester) async {
    final (_, port) = _port();
    await _pump(tester, port: port);
    await _fillMinimalForm(tester);
    await tester.tap(find.byKey(CreateFlowView.deployButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(OrganizerPollCard.nextActionKey));
    await tester.pumpAndSettle();

    expect(find.text('SHARE THIS POLL'), findsOneWidget);
    expect(find.byKey(DistributeSheet.qrKey), findsOneWidget);
    expect(
      find.text(shareLinkForPoll(_pollAddress, module: 'anon-vote')),
      findsOneWidget,
      reason: 'the share sheet and the JOIN grammar must agree on the link',
    );
    // This test device has no NFC: the tile is dropped, not greyed.
    expect(find.byKey(DistributeSheet.nfcTileKey), findsNothing);
  });
}
