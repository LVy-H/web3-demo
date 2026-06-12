// R3: the real YOU space. Thin glue only — reads the DI graph and AppState,
// then delegates everything to feature_you's [YouSpaceView]. The router does
// not change; only this file did (R2f contract).
import 'package:core_chain/chain_reader.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_crypto/proof/proof_service_factory.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/identity_store.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../build_info.dart';
import '../routing/safe_navigation.dart';
import '../state/app_state.dart';

class YouSpaceScreen extends StatelessWidget {
  const YouSpaceScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final reader = context.read<ChainReader>();
    final relay = context.read<RelayClient>();
    final proof = context.read<ProofService>();
    return YouSpaceView(
      identityStore: context.read<IdentityStore>(),
      // Pass changes must reach AppState's identity presence — the router
      // re-evaluates guards against it via refreshListenable.
      onPassChanged: appState.refreshIdentity,
      // Registration-code derivation needs a prover; elsewhere the advanced
      // panel shows its honest "not on this device" copy.
      deriveRegistrationCode: proofServiceAvailable
          ? proof.deriveCommitment
          : null,
      receiptsStore: SecureReceiptsStore(),
      onOpenVerify: (poll, code) {
        final query = <String, String>{
          if (poll != null && poll.isNotEmpty) 'poll': poll,
          if (code != null && code.isNotEmpty) 'nullifier': code,
        };
        context.pushOnce(
          Uri(
            path: '/you/verify',
            queryParameters: query.isEmpty ? null : query,
          ).toString(),
        );
      },
      networkConfigStore: context.read<NetworkConfigStore>(),
      // R2f re-probe hook: a saved network change re-runs the capability
      // probe (relayer reachability etc.) immediately.
      onNetworkConfigChanged: appState.refreshCapabilities,
      checkChain: () async {
        try {
          await reader.getAllPolls();
          return true;
        } catch (_) {
          return false;
        }
      },
      checkRelayer: () async => await relay.getRelayerInfo() != null,
      canProve: appState.capabilities.canProve,
      // Release builds stamp the git tag here (see build_info.dart); the
      // About screen hides the row when null (local/dev builds).
      appVersion: tesseraBuildVersion,
    );
  }
}
