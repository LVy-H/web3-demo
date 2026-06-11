// Module resolution with a fake reader: every module type + unknown +
// unreachable + caching (R2f deliverable 2).
import 'package:core_domain/models/poll_info.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tessera/routing/poll_module_resolver.dart';

PollInfo info(String address, String moduleType) => PollInfo(
  pollAddress: address,
  moduleType: moduleType,
  title: '$moduleType poll',
  description: '',
  creator: '0x2222222222222222222222222222222222222222',
  createdAt: BigInt.one,
);

const modules = [
  'anon-vote',
  'blind-vote',
  'approval-vote',
  'ranked-vote',
  'quadratic-vote',
  'survey-vote',
  'live-vote',
];

/// Addresses 0x00..01, 0x00..02, … per module.
String addrFor(int i) => '0x${(i + 1).toRadixString(16).padLeft(40, '0')}';

void main() {
  late int fetchCount;
  late PollModuleResolver resolver;

  setUp(() {
    fetchCount = 0;
    resolver = PollModuleResolver(
      fetchPolls: () async {
        fetchCount++;
        return [
          for (var i = 0; i < modules.length; i++) info(addrFor(i), modules[i]),
        ];
      },
    );
  });

  test('resolves the on-chain module type for every module', () async {
    for (var i = 0; i < modules.length; i++) {
      final resolution = await resolver.resolve(addrFor(i));
      expect(
        resolution,
        isA<PollModuleResolved>().having(
          (r) => r.moduleType,
          'moduleType',
          modules[i],
        ),
        reason: 'module ${modules[i]}',
      );
    }
  });

  test(
    'address match is case-insensitive (checksummed vs lowercase)',
    () async {
      final upper = addrFor(0).toUpperCase().replaceFirst('0X', '0x');
      final resolution = await resolver.resolve(upper);
      expect(resolution, isA<PollModuleResolved>());
    },
  );

  test('unknown address resolves to typed PollUnknown, not a crash', () async {
    final resolution = await resolver.resolve(
      '0xdEAD00000000000000000000000000000000beEF',
    );
    expect(
      resolution,
      isA<PollUnknown>().having(
        (r) => r.messageKey,
        'messageKey',
        'error.poll.unknown',
      ),
    );
  });

  test('non-address input is PollUnknown without hitting the chain', () async {
    final resolution = await resolver.resolve('not-an-address');
    expect(resolution, isA<PollUnknown>());
    expect(fetchCount, 0);
  });

  test('reader failure resolves to retryable PollLookupFailed', () async {
    final failing = PollModuleResolver(
      fetchPolls: () async => throw Exception('rpc down'),
    );
    final resolution = await failing.resolve(addrFor(0));
    expect(
      resolution,
      isA<PollLookupFailed>().having(
        (r) => r.messageKey,
        'messageKey',
        'error.poll.unreachable',
      ),
    );
  });

  test('successful resolutions are cached per address', () async {
    await resolver.resolve(addrFor(0));
    await resolver.resolve(addrFor(0));
    await resolver.resolve(addrFor(0).toUpperCase().replaceFirst('0X', '0x'));
    expect(fetchCount, 1);

    // A different address is a fresh lookup.
    await resolver.resolve(addrFor(1));
    expect(fetchCount, 2);
  });

  test('failures are NOT cached — a retry can succeed', () async {
    var calls = 0;
    final flaky = PollModuleResolver(
      fetchPolls: () async {
        calls++;
        if (calls == 1) throw Exception('transient');
        return [info(addrFor(0), 'anon-vote')];
      },
    );
    expect(await flaky.resolve(addrFor(0)), isA<PollLookupFailed>());
    expect(await flaky.resolve(addrFor(0)), isA<PollModuleResolved>());
  });

  test(
    'unknown is not cached as a success (poll may be created later)',
    () async {
      var created = false;
      final lateRegistry = PollModuleResolver(
        fetchPolls: () async =>
            created ? [info(addrFor(0), 'anon-vote')] : const <PollInfo>[],
      );
      expect(await lateRegistry.resolve(addrFor(0)), isA<PollUnknown>());
      created = true;
      expect(await lateRegistry.resolve(addrFor(0)), isA<PollModuleResolved>());
    },
  );
}
