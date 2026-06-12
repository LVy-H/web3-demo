// Live-voter flow (R3): one screen per LiveVoterMachine state, with the
// stalled state's recovery actions (RETRY / RESCAN / LEAVE) exercised
// end-to-end against the real machine over a fake port + manual ticker
// (no wall-clock timers, no network).
import 'dart:async';

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/live_journeys.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide Timeout;

import 'package:tessera/spaces/live_vote_screen.dart';

const addr = '0x1111111111111111111111111111111111111111';

final caps = Capabilities.none.copyWith(canProve: true, canScanQr: true);

class FakeLiveVoterPort implements LiveVoterPort {
  int announceCalls = 0;
  Object? announceError;
  Future<void>? proofGate; // lets a test HOLD the proving state open
  Future<void>? relayGate;
  Object? relayError;

  @override
  Future<LiveTicket> parseTicket(String raw) async => LiveTicket(raw.trim());

  @override
  Future<LiveAnnouncement> announce(LiveTicket ticket) async {
    announceCalls++;
    final error = announceError;
    if (error != null) throw error;
    return const LiveAnnouncement(commitment: '123', confirmationCode: '0427');
  }

  @override
  Future<LiveAdmission?> pollAdmission(LiveAnnouncement announcement) async =>
      null; // admission is driven through machine events in these tests

  @override
  Future<bool> hostAlive() async => true;

  @override
  Future<Object> generateProof(
    LiveAnnouncement announcement,
    int option,
  ) async {
    await proofGate;
    return 'proof-$option';
  }

  @override
  Future<String> relayBallot(int option, Object proof) async {
    await relayGate;
    final error = relayError;
    if (error != null) throw error;
    return '0xreceipt';
  }
}

/// Tick-on-demand cadence: no test ever advances it, so the pending state
/// never spins real timers (timeout/host-gone are driven as machine events).
class ManualTicker implements LiveTicker {
  final StreamController<void> _ticks = StreamController<void>.broadcast();

  @override
  Stream<void> every(Duration interval) => _ticks.stream;
}

const admission = LiveAdmission(options: ['Tea', 'Coffee'], phase: 0);

void main() {
  late FakeLiveVoterPort port;
  late LiveVoterMachine machine;

  setUp(() {
    port = FakeLiveVoterPort();
    machine = LiveVoterMachine(
      port: port,
      ticker: ManualTicker(),
      capabilities: caps,
    );
  });

  Future<List<String>> pumpScreen(
    WidgetTester tester, {
    String? ticket,
    String? scanResult,
  }) async {
    final recorded = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: LiveVoteScreen(
          address: addr,
          ticket: ticket,
          machineBuilder: (_) => machine,
          navigateOverride: (_, location) => recorded.add(location),
          scanTicket: (_) async => scanResult,
        ),
      ),
    );
    return recorded;
  }

  /// Drives the real machine: needsTicket → joining → pending.
  Future<void> reachPending(WidgetTester tester) async {
    await machine.advance(const LiveTicketProvided('wire1'));
    await tester.pump(); // joining effect completes → pending
    expect(machine.state, isA<LiveVoterPending>());
  }

  group('entry (needsTicket)', () {
    testWidgets('offers scan + paste on a scanning device', (tester) async {
      await pumpScreen(tester);
      expect(find.byKey(const Key('live-scan-ticket')), findsOneWidget);
      expect(find.byKey(const Key('live-ticket-field')), findsOneWidget);
    });

    testWidgets('hides the scan button when the device cannot scan', (
      tester,
    ) async {
      machine = LiveVoterMachine(
        port: port,
        ticker: ManualTicker(),
        capabilities: caps.copyWith(canScanQr: false),
      );
      await pumpScreen(tester);
      expect(find.byKey(const Key('live-scan-ticket')), findsNothing);
      expect(find.byKey(const Key('live-ticket-field')), findsOneWidget);
    });

    testWidgets('a deep-linked ticket auto-joins into pending', (tester) async {
      await pumpScreen(tester, ticket: 'wire-from-qr');
      await tester.pump();
      expect(machine.state, isA<LiveVoterPending>());
    });

    testWidgets('a pasted invite joins via the field', (tester) async {
      await pumpScreen(tester);
      await tester.enterText(
        find.byKey(const Key('live-ticket-field')),
        'pasted-wire',
      );
      await tester.tap(find.byKey(const Key('live-ticket-join')));
      await tester.pump();
      await tester.pump();
      expect(machine.state, isA<LiveVoterPending>());
    });
  });

  group('pending', () {
    testWidgets('shows the BIG confirmation code for the host', (tester) async {
      await pumpScreen(tester);
      await reachPending(tester);
      await tester.pump();
      expect(find.text('0427'), findsOneWidget);
      expect(find.text('SHOW THIS TO THE HOST'), findsOneWidget);
      // Liveness affordance while the bounded wait runs.
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('stalled recovery', () {
    testWidgets('timeout → stalled with RETRY / RESCAN / LEAVE', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reachPending(tester);
      await machine.advance(const Timeout());
      await tester.pump();
      expect(find.text('STILL WAITING…'), findsOneWidget);
      expect(find.byKey(const Key('live-retry')), findsOneWidget);
      expect(find.byKey(const Key('live-rescan')), findsOneWidget);
      expect(find.byKey(const Key('live-leave')), findsOneWidget);
    });

    testWidgets('RETRY re-announces and lands back in pending', (tester) async {
      await pumpScreen(tester);
      await reachPending(tester);
      await machine.advance(const Timeout());
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-retry')));
      await tester.pump();
      await tester.pump();
      expect(port.announceCalls, 2);
      expect(machine.state, isA<LiveVoterPending>());
      expect(find.text('0427'), findsOneWidget);
    });

    testWidgets('RESCAN returns to the ticket entry', (tester) async {
      await pumpScreen(tester);
      await reachPending(tester);
      await machine.advance(const Timeout());
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-rescan')));
      await tester.pump();
      expect(machine.state, isA<LiveVoterNeedsTicket>());
      expect(find.byKey(const Key('live-ticket-field')), findsOneWidget);
    });

    testWidgets('LEAVE exits to the voter home', (tester) async {
      final recorded = await pumpScreen(tester);
      await reachPending(tester);
      await machine.advance(const Timeout());
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-leave')));
      await tester.pump();
      await tester.pump();
      expect(machine.state, isA<LiveVoterLeft>());
      expect(recorded, ['/vote']);
    });

    testWidgets('host gone reads as a host problem, not a user error', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reachPending(tester);
      await machine.advance(const LiveHostUnreachable());
      await tester.pump();
      expect(find.text('CAN’T REACH THE HOST'), findsOneWidget);
      expect(find.byKey(const Key('live-retry')), findsOneWidget);
    });

    testWidgets('an ENDED poll offers only LEAVE (no retry into nothing)', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reachPending(tester);
      // Admission arriving with phase 2 routes admitted → stalled(pollEnded).
      await machine.advance(
        const LiveAdmissionConfirmed(
          LiveAdmission(options: ['Tea', 'Coffee'], phase: 2),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('VOTING HAS ENDED'), findsOneWidget);
      expect(find.byKey(const Key('live-retry')), findsNothing);
      expect(find.byKey(const Key('live-rescan')), findsNothing);
      expect(find.byKey(const Key('live-leave')), findsOneWidget);
    });

    testWidgets('a rejected invite lands in joinFailed with a way out', (
      tester,
    ) async {
      port.announceError = StateError('relayer said no');
      await pumpScreen(tester, ticket: 'bad-wire');
      await tester.pump();
      expect(machine.state, isA<LiveVoterJoinFailed>());
      expect(find.text('THAT INVITE DIDN’T WORK'), findsOneWidget);
      expect(find.byKey(const Key('live-retry')), findsOneWidget);
      expect(find.byKey(const Key('live-rescan')), findsOneWidget);
    });
  });

  group('admitted → ballot → done', () {
    Future<void> reachBallot(WidgetTester tester) async {
      await reachPending(tester);
      await machine.advance(const LiveAdmissionConfirmed(admission));
      await tester.pump(); // admitted auto-routes by phase (0 → waiting)
      await machine.advance(const ExternalPhaseChanged(1));
      await tester.pump();
      expect(machine.state, isA<LiveVoterBallotOpen>());
    }

    testWidgets('admitted at phase 0 waits for the host to open voting', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reachPending(tester);
      await machine.advance(const LiveAdmissionConfirmed(admission));
      await tester.pump();
      await tester.pump();
      expect(machine.state, isA<LiveVoterWaitingForOpen>());
      expect(
        find.text('You’re in — waiting for the host to open voting.'),
        findsOneWidget,
      );
    });

    testWidgets('the ballot renders the admission options, single-choice', (
      tester,
    ) async {
      await pumpScreen(tester);
      await reachBallot(tester);
      expect(find.text('Tea'), findsOneWidget);
      expect(find.text('Coffee'), findsOneWidget);
      // Nothing selected yet → CAST disabled (the key sits on the wrapper;
      // the tappable FilledButton is its descendant).
      final cast = find.descendant(
        of: find.byKey(const Key('live-cast')),
        // FilledButton.icon builds a private FilledButton SUBTYPE, so an
        // exact byType(FilledButton) would miss it.
        matching: find.bySubtype<FilledButton>(),
      );
      expect(tester.widget<FilledButton>(cast).onPressed, isNull);
      await tester.tap(find.byKey(const Key('live-option-1')));
      await tester.pump();
      expect(tester.widget<FilledButton>(cast).onPressed, isNotNull);
    });

    testWidgets('casting shows the jargon-free proving copy', (tester) async {
      final gate = Completer<void>();
      port.proofGate = gate.future;
      await pumpScreen(tester);
      await reachBallot(tester);
      await tester.tap(find.byKey(const Key('live-option-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-cast')));
      await tester.pump();
      expect(machine.state, isA<LiveVoterProvingInProgress>());
      expect(
        find.text('Generating your private vote (~10 s)…'),
        findsOneWidget,
      );
      gate.complete(); // release the prover so the test ends settled
      await tester.pump();
      await tester.pump();
    });

    testWidgets('done shows the receipt and links to You › receipts', (
      tester,
    ) async {
      final recorded = await pumpScreen(tester);
      await reachBallot(tester);
      await tester.tap(find.byKey(const Key('live-option-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-cast')));
      await tester.pump(); // proving completes
      await tester.pump(); // relaying completes
      await tester.pump();
      expect(machine.state, isA<LiveVoterDone>());
      expect(find.text('Your vote is in.'), findsOneWidget);
      expect(find.text('0xreceipt'), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-receipts')));
      expect(recorded, ['/you']);
    });

    testWidgets('a failed relay is retryable back into the ballot', (
      tester,
    ) async {
      port.relayError = StateError('relayer down');
      await pumpScreen(tester);
      await reachBallot(tester);
      await tester.tap(find.byKey(const Key('live-option-0')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('live-cast')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(machine.state, isA<LiveVoterCastFailed>());
      expect(find.text('YOUR VOTE DIDN’T GO THROUGH'), findsOneWidget);
      await tester.tap(find.byKey(const Key('live-retry')));
      await tester.pump();
      expect(machine.state, isA<LiveVoterBallotOpen>());
      expect(find.text('Tea'), findsOneWidget);
    });
  });
}
