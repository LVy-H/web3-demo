// Shared test seam: the PRODUCTION composition with only the pieces that
// would touch platform channels (secure storage) or the network (relayer
// probe, registry fetch) swapped for in-memory/fake implementations.
// Everything else — chain reader over the bundled ABIs, relay client, proof
// service, capability prober, app state, provider list — is the real wiring.
import 'package:core_domain/models/poll_info.dart';
import 'package:core_storage/blind_commit_store.dart';
import 'package:core_storage/created_polls_store.dart';
import 'package:core_storage/identity_store.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:core_storage/org_key_store.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'package:tessera/di/app_dependencies.dart';

Future<AppDependencies> buildTestDependencies({
  Future<List<PollInfo>> Function()? fetchPolls,
  bool relayerReachable = false,
}) {
  // CachingAssetBundle stores load futures bound to the zone that created
  // them. testWidgets runs each test in its own FakeAsync zone, so awaiting
  // an ABI future cached by a PREVIOUS test deadlocks the suite (the
  // completion microtask lands in a fake zone nobody pumps; the per-test
  // timeout is fake-clocked too, so the suite wedges for the 10-minute
  // real-time watchdog PER TEST). Evict between tests so every production()
  // call fetches in the current test's zone.
  rootBundle.clear();
  return AppDependencies.production(
    networkConfigStore: InMemoryNetworkConfigStore(),
    identityStore: InMemoryIdentityStore(),
    createdPollsStore: InMemoryCreatedPollsStore(),
    blindCommitStore: InMemoryBlindCommitStore(),
    orgKeyStore: InMemoryOrgKeyStore(),
    relayerHealthCheck: (_) async => relayerReachable,
    fetchPolls: fetchPolls ?? () async => const <PollInfo>[],
  );
}

PollInfo testPollInfo(String address, String moduleType, {String? title}) =>
    PollInfo(
      pollAddress: address,
      moduleType: moduleType,
      title: title ?? '$moduleType poll',
      description: '',
      creator: '0x2222222222222222222222222222222222222222',
      createdAt: BigInt.one,
    );
