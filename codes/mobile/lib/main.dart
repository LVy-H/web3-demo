import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'config.dart';
import 'data/repositories/poll_repository.dart';
import 'data/repositories/verify_repository.dart';
import 'data/services/chain_reader.dart';
import 'data/services/proof_service.dart';
import 'data/services/proof_service_factory.dart';
import 'data/services/relay_client.dart';
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

  final reader = ChainReader(
    rpcUrl: AppConfig.rpcUrl,
    izkPollAbiJson: _abiArray(izkPollAbi),
    registryAbiJson: _abiArray(registryAbi),
    anonVotingAbiJson: _abiArray(anonAbi),
    registryAddress: AppConfig.registryAddress,
  );

  runApp(ZkVoteApp(reader: reader));
}

class ZkVoteApp extends StatelessWidget {
  final ChainReader reader;
  const ZkVoteApp({super.key, required this.reader});

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
      ],
      child: MaterialApp.router(
        title: 'ZK Vote',
        debugShowCheckedModeBanner: false,
        theme: buildDarkBauhausTheme(),
        routerConfig: buildRouter(),
      ),
    );
  }
}
