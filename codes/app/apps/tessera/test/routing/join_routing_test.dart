// JoinTarget → route mapping: one assertion set per target type
// (R2f deliverable 5).
import 'package:feature_join/feature_join.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/routing/join_routing.dart';

void main() {
  const addr = '0x1111111111111111111111111111111111111111';

  test('PollTarget maps to the single /poll/:address route', () {
    expect(locationForJoinTarget(const PollTarget(addr)), '/poll/$addr');
  });

  test(
    'PollTarget DROPS the legacy ?module= hint (on-chain resolver wins)',
    () {
      expect(
        locationForJoinTarget(const PollTarget(addr, module: 'ranked-vote')),
        '/poll/$addr',
        reason: 'the route must never carry a module guess',
      );
    },
  );

  test('LiveVoteTarget maps to /live/:address/vote with the ticket', () {
    final location = locationForJoinTarget(
      const LiveVoteTarget(addr, ticket: 'a b+c'),
    );
    final uri = Uri.parse(location);
    expect(uri.path, '/live/$addr/vote');
    expect(uri.queryParameters['t'], 'a b+c');
  });

  test('LiveVoteTarget without a ticket carries no query', () {
    expect(
      locationForJoinTarget(const LiveVoteTarget(addr)),
      '/live/$addr/vote',
    );
  });

  test('LiveHostTarget maps to /live/:address/host', () {
    expect(
      locationForJoinTarget(const LiveHostTarget(addr)),
      '/live/$addr/host',
    );
  });

  test('VerifyTarget maps to /you/verify with both halves', () {
    final uri = Uri.parse(
      locationForJoinTarget(const VerifyTarget(poll: addr, nullifier: '12345')),
    );
    expect(uri.path, '/you/verify');
    expect(uri.queryParameters, {'poll': addr, 'nullifier': '12345'});
  });

  test(
    'VerifyTarget passes partial halves through (verify prompts the rest)',
    () {
      expect(
        Uri.parse(
          locationForJoinTarget(const VerifyTarget(nullifier: '9')),
        ).queryParameters,
        {'nullifier': '9'},
      );
      expect(locationForJoinTarget(const VerifyTarget()), '/you/verify');
    },
  );

  test('CodeTarget maps to the /join/resolve placeholder with TES- form', () {
    final uri = Uri.parse(locationForJoinTarget(const CodeTarget('7Q4MZ2')));
    expect(uri.path, '/join/resolve');
    expect(uri.queryParameters['code'], 'TES-7Q4MZ2');
  });

  test('UnknownTarget maps to the typed error route with the parse reason', () {
    final uri = Uri.parse(
      locationForJoinTarget(const UnknownTarget('not a tessera link')),
    );
    expect(uri.path, '/error');
    expect(uri.queryParameters['messageKey'], kJoinUnrecognizedKey);
    expect(uri.queryParameters['detail'], 'not a tessera link');
  });

  test('mapping is total over the real grammar output', () {
    for (final raw in [
      'tessera://poll/$addr?module=ranked-vote',
      'tessera://live/$addr/vote?t=w1',
      'tessera://live/$addr/host',
      'tessera://verify?poll=$addr&nullifier=1',
      'TES-7Q4MZ2',
      'complete garbage ???',
    ]) {
      final location = locationForJoinTarget(parseJoinInput(raw));
      expect(location, startsWith('/'), reason: 'for input: $raw');
    }
  });
}
