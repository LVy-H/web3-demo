import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import 'config.dart';
import 'data/repositories/poll_repository.dart';
import 'data/services/chain_reader.dart';
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

  runApp(ZkVoteApp(repository: ChainPollRepository(reader)));
}

class ZkVoteApp extends StatelessWidget {
  final PollRepository repository;
  const ZkVoteApp({super.key, required this.repository});

  @override
  Widget build(BuildContext context) {
    return Provider<PollRepository>.value(
      value: repository,
      child: MaterialApp.router(
        title: 'ZK Vote',
        debugShowCheckedModeBanner: false,
        theme: buildDarkBauhausTheme(),
        routerConfig: buildRouter(),
      ),
    );
  }
}
