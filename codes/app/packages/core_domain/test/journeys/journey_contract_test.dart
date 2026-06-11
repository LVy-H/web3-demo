import 'dart:async';

import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/guards.dart';
import 'package:core_domain/journeys/journey.dart';
import 'package:core_domain/journeys/policy.dart';
// `hide`: the journey contract's Retry/Timeout events share names with
// package:test configuration types we don't use here.
import 'package:test/test.dart' hide Retry, Timeout;

import 'demo_journey.dart';

/// Drains the event queue so fire-and-forget effect completions land.
Future<void> settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('JourneyMachine (via reference DemoMachine)', () {
    test('legal transition: Idle --DemoStart--> WorkingInProgress', () async {
      final machine = DemoMachine(effect: (token) => Completer<void>().future);
      addTearDown(machine.dispose);

      expect(machine.state, isA<DemoIdle>());
      await machine.advance(const DemoStart());
      expect(machine.state, isA<DemoWorkingInProgress>());
      expect(machine.state.id, 'demo.workingInProgress');
    });

    test(
      'illegal transition throws JourneyViolation, state unchanged',
      () async {
        final machine = DemoMachine(effect: (token) async {});
        addTearDown(machine.dispose);

        await expectLater(
          machine.advance(const Timeout()),
          throwsA(isA<JourneyViolation>()),
        );
        expect(machine.state, isA<DemoIdle>());
      },
    );

    test(
      'guard-rejected transition throws JourneyViolation(guardRejected)',
      () async {
        final machine = DemoMachine(effect: (token) async {});
        addTearDown(machine.dispose);

        await expectLater(
          machine.advance(const DemoStart(allowed: false)),
          throwsA(
            isA<JourneyViolation>().having(
              (v) => v.guardRejected,
              'guardRejected',
              isTrue,
            ),
          ),
        );
        expect(machine.state, isA<DemoIdle>());
      },
    );

    test('terminal state accepts no events', () async {
      final machine = DemoMachine(effect: (token) async {});
      addTearDown(machine.dispose);

      await machine.advance(const DemoStart());
      await settle();
      expect(machine.state, isA<DemoDone>());
      expect(machine.state.isTerminal, isTrue);

      await expectLater(
        machine.advance(const Refresh()),
        throwsA(isA<JourneyViolation>()),
      );
    });

    test('effect success drives WorkingInProgress --> Done', () async {
      final gate = Completer<void>();
      final machine = DemoMachine(effect: (token) => gate.future);
      addTearDown(machine.dispose);

      await machine.advance(const DemoStart());
      expect(machine.state, isA<DemoWorkingInProgress>());

      gate.complete();
      await settle();
      expect(machine.state, isA<DemoDone>());
    });

    test('effect failure --> typed error state --> Retry recovers', () async {
      var attempts = 0;
      final machine = DemoMachine(
        effect: (token) async {
          attempts++;
          if (attempts == 1) throw StateError('relayer unreachable');
        },
      );
      addTearDown(machine.dispose);

      await machine.advance(const DemoStart());
      await settle();

      // Failure is a typed state with a named recovery event — never a
      // stuck busy flag.
      expect(machine.state, isA<DemoFailed>());
      final failed = machine.state as DemoFailed;
      expect(failed.cause, isA<StateError>());
      expect(failed.recoveryEvent, isA<Retry>());
      expect(failed.messageKey, 'error.demoFailed');

      await machine.advance(failed.recoveryEvent);
      await settle();
      expect(machine.state, isA<DemoDone>());
      expect(attempts, 2);
    });

    test('leaving an InProgress state cancels its token', () async {
      final gate = Completer<void>();
      final machine = DemoMachine(effect: (token) => gate.future);
      addTearDown(machine.dispose);

      await machine.advance(const DemoStart());
      final working = machine.state as DemoWorkingInProgress;
      expect(working.cancellation.isCancelled, isFalse);

      gate.completeError(StateError('boom'));
      await settle(); // effect fails -> DemoFailed
      expect(machine.state, isA<DemoFailed>());
      expect(working.cancellation.isCancelled, isTrue);
    });

    test('dispose cancels the in-flight effect token', () async {
      final machine = DemoMachine(effect: (token) => Completer<void>().future);

      await machine.advance(const DemoStart());
      final working = machine.state as DemoWorkingInProgress;

      machine.dispose();
      expect(working.cancellation.isCancelled, isTrue);
      await expectLater(
        machine.advance(const DemoSucceeded()),
        throwsStateError,
      );
    });

    test('listeners are notified of every transition, in order', () async {
      final machine = DemoMachine(effect: (token) async {});
      addTearDown(machine.dispose);

      final seen = <String>[];
      final sub = machine.states.listen((s) => seen.add(s.id));
      addTearDown(sub.cancel);

      await machine.advance(const DemoStart());
      await settle();

      expect(seen, ['demo.workingInProgress', 'demo.done']);
    });

    test('every state surfaces its one NextAction', () {
      const idle = DemoIdle();
      expect(idle.nextAction!.labelKey, 'action.start');
      expect(idle.nextAction!.type, NextActionType.submit);
      expect(idle.nextAction!.enabled, isTrue);

      final working = DemoWorkingInProgress(CancellationToken());
      expect(working.nextAction!.type, NextActionType.wait);

      const failed = DemoFailed('cause');
      expect(failed.nextAction!.type, NextActionType.retry);
      expect(failed.nextAction!.labelKey, 'action.retry');

      const done = DemoDone();
      expect(done.nextAction, isNull);

      const disabled = NextAction(
        labelKey: 'action.castVote',
        type: NextActionType.submit,
        disabledReasonKey: 'reason.deviceCannotProve',
      );
      expect(disabled.enabled, isFalse);
    });
  });

  group('Capabilities', () {
    test('none is all-off; has() mirrors the named fields', () {
      expect(Capability.values.where(Capabilities.none.has), isEmpty);

      final probed = Capabilities.none.copyWith(
        canProve: true,
        relayerAvailable: true,
        reasons: const {Capability.nfc: 'reason.noNfcHardware'},
      );
      expect(probed.has(Capability.prove), isTrue);
      expect(probed.has(Capability.relayer), isTrue);
      expect(probed.has(Capability.nfc), isFalse);
      expect(probed.reasonFor(Capability.nfc), 'reason.noNfcHardware');
      expect(probed.reasonFor(Capability.prove), isNull);
    });

    test('value equality', () {
      const a = Capabilities(
        canProve: true,
        canSign: false,
        canScanQr: true,
        hasNfc: false,
        hasBle: false,
        canUseWallet: false,
        relayerAvailable: true,
        reasons: {Capability.sign: 'reason.noSigner'},
      );
      const b = Capabilities(
        canProve: true,
        canSign: false,
        canScanQr: true,
        hasNfc: false,
        hasBle: false,
        canUseWallet: false,
        relayerAvailable: true,
        reasons: {Capability.sign: 'reason.noSigner'},
      );
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(Capabilities.none)));
    });
  });

  group('Policies', () {
    test('privacy defaults are sealedUntilClose and unlisted (spec §5)', () {
      expect(ResultsPolicy.defaultPolicy, ResultsPolicy.sealedUntilClose);
      expect(PollVisibility.defaultVisibility, PollVisibility.unlisted);
    });
  });

  group('RouteGuard', () {
    test('pure (state, capabilities) -> allow | redirect | block', () {
      // A ballot guard like R2f will write: entry to a ballot state needs
      // a proving device; terminal states bounce to the receipt.
      final guard = RouteGuard.from((state, caps) {
        if (state.isTerminal) return const GuardResult.redirect('demo.done');
        if (!caps.canProve) {
          return const GuardResult.block('reason.deviceCannotProve');
        }
        return const GuardResult.allow();
      });

      final working = DemoWorkingInProgress(CancellationToken());
      expect(
        guard.evaluate(working, Capabilities.none),
        const GuardBlock('reason.deviceCannotProve'),
      );
      expect(
        guard.evaluate(working, Capabilities.none.copyWith(canProve: true)),
        isA<GuardAllow>(),
      );
      expect(
        guard.evaluate(const DemoDone(), Capabilities.none),
        const GuardRedirect('demo.done'),
      );

      // Exhaustive switch over the sealed result type.
      final result = guard.evaluate(working, Capabilities.none);
      final verdict = switch (result) {
        GuardAllow() => 'allow',
        GuardRedirect(:final targetStateId) => 'redirect:$targetStateId',
        GuardBlock(:final reasonKey) => 'block:$reasonKey',
      };
      expect(verdict, 'block:reason.deviceCannotProve');
    });
  });
}
