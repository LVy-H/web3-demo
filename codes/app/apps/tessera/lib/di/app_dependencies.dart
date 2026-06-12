/// DI composition root (R2f deliverable 6).
///
/// ONE production wiring, used by `main()` AND pumped as-is by the
/// composition-root widget test — so a provider missing from production can
/// never pass tests (the historical ProviderNotFound-only-in-prod bug
/// class). Tests override only what must not touch platform channels or the
/// network (secure storage, the relayer health check, the registry fetch).
library;

import 'dart:convert';

import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/config.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_crypto/proof/proof_service_factory.dart';
import 'package:core_domain/models/poll_info.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/blind_commit_store.dart';
import 'package:core_storage/created_polls_store.dart';
import 'package:core_storage/identity_store.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:core_storage/org_key_store.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../capabilities/capability_prober.dart';
import '../routing/poll_module_resolver.dart';
import '../state/app_state.dart';

/// Hardhat artifacts wrap the ABI as `{"abi": [...]}`; ChainReader wants the
/// bare array string.
String _abiArray(String artifactJson) {
  final decoded = jsonDecode(artifactJson);
  return jsonEncode(decoded is Map ? decoded['abi'] : decoded);
}

class AppDependencies {
  final ChainReader chainReader;
  final RelayClient relayClient;
  final IdentityStore identityStore;
  final CreatedPollsStore createdPollsStore;
  final BlindCommitStore blindCommitStore;
  final OrgKeyStore orgKeyStore;
  final NetworkConfigStore networkConfigStore;
  final ProofService proofService;
  final PollModuleResolver pollModuleResolver;
  final CapabilityProber capabilityProber;
  final AppState appState;

  const AppDependencies({
    required this.chainReader,
    required this.relayClient,
    required this.identityStore,
    required this.createdPollsStore,
    required this.blindCommitStore,
    required this.orgKeyStore,
    required this.networkConfigStore,
    required this.proofService,
    required this.pollModuleResolver,
    required this.capabilityProber,
    required this.appState,
  });

  /// Production wiring. Order matters: the saved network override is applied
  /// to [AppConfig] BEFORE anything reads it (reader, relayer client,
  /// capability prober).
  ///
  /// The optional parameters are test seams ONLY — every default is the real
  /// production object. Widget tests inject in-memory stores (no platform
  /// channels), a fake [relayerHealthCheck] and a fake [fetchPolls] (no
  /// network); everything else stays production.
  static Future<AppDependencies> production({
    NetworkConfigStore? networkConfigStore,
    IdentityStore? identityStore,
    CreatedPollsStore? createdPollsStore,
    BlindCommitStore? blindCommitStore,
    OrgKeyStore? orgKeyStore,
    RelayerHealthCheck? relayerHealthCheck,
    Future<List<PollInfo>> Function()? fetchPolls,
  }) async {
    // 1. Effective network config: overlay a valid saved override, exactly
    //    once, here (see core_chain/config.dart header).
    final configStore = networkConfigStore ?? SecureNetworkConfigStore();
    NetworkConfig? saved;
    try {
      saved = await configStore.load();
    } catch (_) {
      saved = null; // unreadable store never bricks startup
    }
    AppConfig.apply(saved != null && saved.isValidFormat ? saved : null);

    // 2. Chain reader over the bundled ABIs — ALL from core_chain's package
    //    assets, the single canonical R4 copy (the R4 client migration
    //    refreshed the set and retired the app-local PollRegistry.json
    //    workaround that bridged the pre-R4 gap).
    const pkgAbi = 'packages/core_chain/assets/abi';
    // One parallel batch, not five sequential awaits: on web every
    // rootBundle.loadString is an HTTP fetch and runApp() waits on this, so
    // sequential loads put five round-trips on the startup critical path.
    final [izkPollAbi, registryAbi, anonAbi, blindAbi, surveyAbi] =
        await Future.wait([
          rootBundle.loadString('$pkgAbi/IZkPoll.json'),
          rootBundle.loadString('$pkgAbi/PollRegistry.json'),
          rootBundle.loadString('$pkgAbi/ZkAnonVoting.json'),
          rootBundle.loadString('$pkgAbi/ZkBlindVoting.json'),
          rootBundle.loadString('$pkgAbi/ZkSurveyVoting.json'),
        ]);
    final chainReader = ChainReader(
      rpcUrl: AppConfig.rpcUrl,
      izkPollAbiJson: _abiArray(izkPollAbi),
      registryAbiJson: _abiArray(registryAbi),
      anonVotingAbiJson: _abiArray(anonAbi),
      blindVotingAbiJson: _abiArray(blindAbi),
      surveyVotingAbiJson: _abiArray(surveyAbi),
      registryAddress: AppConfig.registryAddress,
    );

    // 3. The rest of the graph.
    final ids = identityStore ?? SecureIdentityStore();
    final prober = CapabilityProber(checkRelayer: relayerHealthCheck);
    return AppDependencies(
      chainReader: chainReader,
      relayClient: RelayClient(baseUrl: AppConfig.relayerUrl),
      identityStore: ids,
      createdPollsStore: createdPollsStore ?? SecureCreatedPollsStore(),
      blindCommitStore: blindCommitStore ?? SecureBlindCommitStore(),
      orgKeyStore: orgKeyStore ?? SecureOrgKeyStore(),
      networkConfigStore: configStore,
      proofService: createProofService(),
      pollModuleResolver: PollModuleResolver(
        fetchPolls: fetchPolls ?? chainReader.getAllPolls,
      ),
      capabilityProber: prober,
      appState: AppState(prober: prober, identityStore: ids),
    );
  }
}

/// THE production provider list. main() and the composition-root test both
/// build the tree from this single function — there is no second wiring to
/// drift.
List<SingleChildWidget> buildAppProviders(AppDependencies deps) => [
  Provider<ChainReader>.value(value: deps.chainReader),
  Provider<RelayClient>.value(value: deps.relayClient),
  Provider<IdentityStore>.value(value: deps.identityStore),
  Provider<CreatedPollsStore>.value(value: deps.createdPollsStore),
  Provider<BlindCommitStore>.value(value: deps.blindCommitStore),
  Provider<OrgKeyStore>.value(value: deps.orgKeyStore),
  Provider<NetworkConfigStore>.value(value: deps.networkConfigStore),
  Provider<ProofService>.value(value: deps.proofService),
  Provider<PollModuleResolver>.value(value: deps.pollModuleResolver),
  Provider<CapabilityProber>.value(value: deps.capabilityProber),
  ChangeNotifierProvider<AppState>.value(value: deps.appState),
];
