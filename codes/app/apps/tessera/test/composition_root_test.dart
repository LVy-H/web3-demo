// Composition-root resolution test (R2f deliverable 6): pump the REAL
// production provider list and assert every provider resolves from a screen
// context — the historical ProviderNotFound-only-in-prod bug class dies in
// CI here.
import 'package:core_chain/chain_reader.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/blind_commit_store.dart';
import 'package:core_storage/created_polls_store.dart';
import 'package:core_storage/identity_store.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:core_storage/org_key_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:tessera/app.dart';
import 'package:tessera/capabilities/capability_prober.dart';
import 'package:tessera/routing/poll_module_resolver.dart';
import 'package:tessera/spaces/vote_space_screen.dart';
import 'package:tessera/state/app_state.dart';

import 'test_dependencies.dart';

void main() {
  testWidgets(
    'every provider in the production composition resolves from a screen',
    (tester) async {
      final deps = await buildTestDependencies();
      await tester.pumpWidget(TesseraApp(dependencies: deps));
      await tester.pumpAndSettle();

      // A context BELOW the provider tree, exactly where screens read from.
      final context = tester.element(find.byType(VoteSpaceScreen));

      expect(context.read<ChainReader>(), same(deps.chainReader));
      expect(context.read<RelayClient>(), same(deps.relayClient));
      expect(context.read<IdentityStore>(), same(deps.identityStore));
      expect(context.read<CreatedPollsStore>(), same(deps.createdPollsStore));
      expect(context.read<BlindCommitStore>(), same(deps.blindCommitStore));
      expect(context.read<OrgKeyStore>(), same(deps.orgKeyStore));
      expect(context.read<NetworkConfigStore>(), same(deps.networkConfigStore));
      expect(context.read<ProofService>(), same(deps.proofService));
      expect(context.read<PollModuleResolver>(), same(deps.pollModuleResolver));
      expect(context.read<CapabilityProber>(), same(deps.capabilityProber));
      expect(context.read<AppState>(), same(deps.appState));
    },
  );

  testWidgets('startup probes complete and land in AppState', (tester) async {
    final deps = await buildTestDependencies(relayerReachable: true);
    await tester.pumpWidget(TesseraApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(
      deps.appState.capabilities.relayerAvailable,
      isTrue,
      reason: 'the injected health check answered true and start() ran',
    );
    expect(deps.appState.hasIdentity, isFalse);
  });
}
