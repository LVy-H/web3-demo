// The run-event console over a faked LiveHostPort: the whole happy path —
// rotating-ticket QR up, admit-by-code, the gated START VOTING (honestly
// disabled until someone is in), turnout, CLOSE — in machine order, because
// the LiveHostMachine's transition table is the only thing sequencing it.
import 'package:core_domain/journeys/live_journeys.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ticker that never ticks: the test drives every transition itself, so
/// queue refreshes come only from the admit action's own result.
class _NeverTicker implements LiveTicker {
  const _NeverTicker();

  @override
  Stream<void> every(Duration interval) => const Stream<void>.empty();
}

class _ScriptedHostPort implements LiveHostPort {
  final List<String> log = [];

  AdmitQueue queue = const AdmitQueue(
    pending: [PendingLiveVoter(commitment: '0xc1', confirmationCode: 'KK7P4Q')],
    admitted: 0,
  );

  @override
  Future<void> loadSession() async => log.add('load');

  @override
  Future<String> rotateTicket() async {
    log.add('rotate');
    return 'tessera://live/0xpoll?t=ticket-1';
  }

  @override
  Future<AdmitQueue> fetchQueue() async => queue;

  @override
  Future<AdmitQueue> confirmVoter(String confirmationCode) async {
    log.add('confirm:$confirmationCode');
    queue = const AdmitQueue(pending: [], admitted: 1, turnout: 0);
    return queue;
  }

  @override
  Future<void> startVoting() async => log.add('start');

  @override
  Future<void> close() async => log.add('close');
}

void main() {
  testWidgets('admit → start → close, with START gated until the first '
      'voter is in the room', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final port = _ScriptedHostPort();
    var exited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: LiveHostConsole(
          port: port,
          ticker: const _NeverTicker(),
          onExit: () => exited = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Session open: the rotating-ticket QR is up and one voter waits.
    expect(find.byKey(LiveHostConsole.ticketQrKey), findsOneWidget);
    expect(find.text('KK7P4Q'), findsOneWidget);

    // START VOTING is honestly disabled — nobody admitted yet.
    final gated = tester.widget<FilledButton>(
      find.byKey(LiveHostConsole.startVotingKey),
    );
    expect(gated.onPressed, isNull);
    expect(
      find.text('Admit at least one voter first.'),
      findsOneWidget,
      reason: 'a disabled action always says why',
    );

    // Admit by code.
    await tester.tap(find.byKey(const Key('admit-KK7P4Q')));
    await tester.pumpAndSettle();
    expect(port.log, contains('confirm:KK7P4Q'));
    expect(find.text('Admit at least one voter first.'), findsNothing);
    final ungated = tester.widget<FilledButton>(
      find.byKey(LiveHostConsole.startVotingKey),
    );
    expect(ungated.onPressed, isNotNull);

    // Start voting → turnout view (counts ballots, never a tally).
    await tester.tap(find.byKey(LiveHostConsole.startVotingKey));
    await tester.pumpAndSettle();
    expect(find.text('VOTING IS OPEN'), findsOneWidget);
    expect(find.text('0 of 1'), findsOneWidget);

    // Close → terminal summary → exit.
    await tester.tap(find.byKey(LiveHostConsole.closeKey));
    await tester.pumpAndSettle();
    expect(find.text('VOTING CLOSED'), findsOneWidget);

    await tester.tap(find.byKey(LiveHostConsole.doneKey));
    expect(exited, isTrue);

    // The machine sequenced the phases: confirm before start before close.
    final confirmAt = port.log.indexOf('confirm:KK7P4Q');
    final startAt = port.log.indexOf('start');
    final closeAt = port.log.indexOf('close');
    expect(confirmAt, lessThan(startAt));
    expect(startAt, lessThan(closeAt));
  });

  testWidgets('a failed close lands in the typed error state with retry — '
      'never a dead end', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final port = _FailingClosePort();
    await tester.pumpWidget(
      MaterialApp(
        home: LiveHostConsole(
          port: port,
          ticker: const _NeverTicker(),
          onExit: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admit-KK7P4Q')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LiveHostConsole.startVotingKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(LiveHostConsole.closeKey));
    await tester.pumpAndSettle();

    expect(find.text('The vote could not be closed.'), findsOneWidget);
    expect(find.byKey(const Key('console-retry')), findsOneWidget);

    port.failClose = false;
    await tester.tap(find.byKey(const Key('console-retry')));
    await tester.pumpAndSettle();
    expect(find.text('VOTING CLOSED'), findsOneWidget);
  });
}

class _FailingClosePort extends _ScriptedHostPort {
  bool failClose = true;

  @override
  Future<void> close() async {
    if (failClose) throw StateError('rpc unreachable');
    await super.close();
  }
}
