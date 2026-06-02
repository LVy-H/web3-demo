import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'config.dart';
import 'data/repositories/blind_repository.dart';
import 'data/repositories/live_host_repository.dart';
import 'data/repositories/poll_repository.dart';
import 'data/repositories/verify_repository.dart';
import 'data/services/blind_commit_store.dart';
import 'data/services/chain_reader.dart';
import 'data/services/chain_writer.dart';
import 'data/services/identity_store.dart';
import 'data/services/poll_creator.dart';
import 'data/services/proof_service.dart';
import 'data/services/proof_service_factory.dart';
import 'data/services/relay_client.dart';
import 'data/services/wallet_service.dart';
import 'router.dart';
import 'ui/core/theme.dart';

/// Extract the ABI array from a hardhat artifact JSON ({ "abi": [...] }).
String _abiArray(String artifactJson) =>
    jsonEncode((jsonDecode(artifactJson) as Map<String, dynamic>)['abi']);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final izkPollAbi = await rootBundle.loadString('assets/abi/IZkPoll.json');
  final registryAbi = await rootBundle.loadString('assets/abi/PollRegistry.json');
  final anonAbi = await rootBundle.loadString('assets/abi/ZkAnonVoting.json');
  final blindAbi = await rootBundle.loadString('assets/abi/ZkBlindVoting.json');

  final registryAbiArr = _abiArray(registryAbi);
  final anonAbiArr = _abiArray(anonAbi);
  final blindAbiArr = _abiArray(blindAbi);

  final reader = ChainReader(
    rpcUrl: AppConfig.rpcUrl,
    izkPollAbiJson: _abiArray(izkPollAbi),
    registryAbiJson: registryAbiArr,
    anonVotingAbiJson: anonAbiArr,
    blindVotingAbiJson: blindAbiArr,
    registryAddress: AppConfig.registryAddress,
  );

  final writer = ChainWriter(
    rpcUrl: AppConfig.rpcUrl,
    chainId: AppConfig.chainId,
    privateKey: AppConfig.devPrivateKey,
  );

  runApp(ZkVoteApp(
    reader: reader,
    writer: writer,
    registryAbiJson: registryAbiArr,
    anonAbiJson: anonAbiArr,
    blindAbiJson: blindAbiArr,
  ));
}

class ZkVoteApp extends StatelessWidget {
  final ChainReader reader;
  final ChainWriter writer;
  final String registryAbiJson;
  final String anonAbiJson;
  final String blindAbiJson;
  const ZkVoteApp({
    super.key,
    required this.reader,
    required this.writer,
    required this.registryAbiJson,
    required this.anonAbiJson,
    required this.blindAbiJson,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<PollRepository>(
          create: (_) => ChainPollRepository(reader),
          dispose: (_, _) => reader.dispose(),
        ),
        Provider<VerifyRepository>(create: (_) => ChainVerifyRepository(reader)),
        Provider<RelayClient>(
          create: (_) => RelayClient(baseUrl: AppConfig.relayerUrl),
          dispose: (_, c) => c.close(),
        ),
        Provider<ProofService>(create: (_) => createProofService()),
        Provider<IdentityStore>(create: (_) => SecureIdentityStore()),
        Provider<ChainWriter>(
          create: (_) => writer,
          dispose: (_, w) => w.dispose(),
        ),
        Provider<BlindCommitStore>(create: (_) => SecureBlindCommitStore()),
        Provider<BlindRepository>(
          create: (ctx) => BlindRepository(
            reader: reader,
            writer: writer,
            commits: ctx.read<BlindCommitStore>(),
            blindAbiJson: blindAbiJson,
          ),
        ),
        Provider<PollCreator>(
          create: (_) => PollCreator(
            writer: writer,
            registryAbiJson: registryAbiJson,
            anonAbiJson: anonAbiJson,
          ),
        ),
        Provider<LiveHostRepository>(
          create: (ctx) => LiveHostRepository(
            relay: ctx.read<RelayClient>(),
            writer: writer,
            anonAbiJson: anonAbiJson,
          ),
        ),
        ChangeNotifierProvider<WalletService>(
          create: (_) => WalletService(
            registryAbiJson: registryAbiJson,
            anonAbiJson: anonAbiJson,
          ),
        ),
      ],
      child: MaterialApp.router(
        title: 'Tessera',
        debugShowCheckedModeBanner: false,
        theme: buildDarkBauhausTheme(),
        routerConfig: buildRouter(),
      ),
    );
  }
}
