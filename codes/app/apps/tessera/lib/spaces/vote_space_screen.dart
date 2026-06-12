// The VOTE space (R3): delegates to feature_vote's home — needs-you /
// waiting / done sections from the local participation record + cheap chain
// phase reads, with the opt-in public DIRECTORY as the secondary tab. The
// router still builds `const VoteSpaceScreen()`; only this file changed.
import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/config.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../routing/safe_navigation.dart';

class VoteSpaceScreen extends StatefulWidget {
  const VoteSpaceScreen({super.key});

  @override
  State<VoteSpaceScreen> createState() => _VoteSpaceScreenState();
}

class _VoteSpaceScreenState extends State<VoteSpaceScreen> {
  // One persistent record per app run; multiple instances share the same
  // backing storage key, so the poll screens' writes show up on refresh.
  final KnownPollsStore _knownPolls = SecureKnownPollsStore();

  /// Directory reads need the R4 registry ABI (getListedPolls), which the
  /// app — not core_chain — ships (see di/app_dependencies.dart). The shell
  /// loads the asset and INJECTS the string, keeping feature_vote free of
  /// asset paths.
  Future<List<ListedPoll>> _fetchDirectory() async {
    final abiJson = await rootBundle.loadString('assets/abi/PollRegistry.json');
    if (!mounted) return const [];
    final reader = ListedPollsReader(
      registryAbiJson: abiJson,
      client: context.read<ChainReader>().client,
      registryAddress: AppConfig.registryAddress,
    );
    return reader.fetchListed();
  }

  @override
  Widget build(BuildContext context) {
    final chainReader = context.read<ChainReader>();
    return VoteHomeScreen(
      knownPolls: _knownPolls,
      fetchPhase: chainReader.getState,
      fetchDirectory: _fetchDirectory,
      // pushOnce: double-taps never stack a second copy of the same page.
      onOpenPoll: (address) => context.pushOnce('/poll/$address'),
      onJoin: () => context.pushOnce('/join'),
    );
  }
}
