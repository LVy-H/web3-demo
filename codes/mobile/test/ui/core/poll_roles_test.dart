import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/ui/core/poll_roles.dart';

void main() {
  const relayer = '0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266';
  const me = '0x1111111111111111111111111111111111111111';
  const other = '0x2222222222222222222222222222222222222222';

  group('pollOwner — meaningful ownership label', () {
    test('owner == relayer → sponsored (relayer-run)', () {
      final o = pollOwner(
        owner: relayer,
        relayerAddress: relayer,
        myAddress: me,
      );
      expect(o.kind, PollOwnerKind.sponsored);
      expect(o.label, 'Sponsored · relayer-run');
      expect(o.address, relayer);
    });

    test('relayer match is case-insensitive', () {
      final o = pollOwner(
        owner: relayer.toLowerCase(),
        relayerAddress: relayer.toUpperCase(),
        myAddress: null,
      );
      expect(o.kind, PollOwnerKind.sponsored);
    });

    test('owner == my address → you', () {
      final o = pollOwner(owner: me, relayerAddress: relayer, myAddress: me);
      expect(o.kind, PollOwnerKind.you);
      expect(o.label, 'You');
    });

    test('sponsored takes priority over you', () {
      // If the owner is the relayer it is sponsored, never "you".
      final o = pollOwner(
        owner: relayer,
        relayerAddress: relayer,
        myAddress: relayer,
      );
      expect(o.kind, PollOwnerKind.sponsored);
    });

    test('a different creator → other (short address, not Sponsored/You)', () {
      final o = pollOwner(owner: other, relayerAddress: relayer, myAddress: me);
      expect(o.kind, PollOwnerKind.other);
      expect(o.label, isNot(contains('Sponsored')));
      expect(o.label, isNot('You'));
      expect(o.address, other);
    });

    test('no relayer/my address known → other (safe fallback)', () {
      final o = pollOwner(owner: other);
      expect(o.kind, PollOwnerKind.other);
      expect(o.address, other);
    });
  });
}
