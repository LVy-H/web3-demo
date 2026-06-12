// R3: the real ORGANIZE space. Thin glue only — builds the relayer-backed
// organizer port from the DI graph, then delegates everything to
// feature_organize's [OrganizeSpaceView]. The router did not change; only
// this file did (R2f contract).
import 'package:core_chain/chain_reader.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/created_polls_store.dart';
import 'package:design_system/theme.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../routing/safe_navigation.dart';
import '../state/app_state.dart';
import 'organize_wire.dart';

class OrganizeSpaceScreen extends StatefulWidget {
  const OrganizeSpaceScreen({super.key});

  @override
  State<OrganizeSpaceScreen> createState() => _OrganizeSpaceScreenState();
}

class _OrganizeSpaceScreenState extends State<OrganizeSpaceScreen> {
  Future<RelayOrganizerPort>? _port;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _port ??= buildOrganizerPort(
      relay: context.read<RelayClient>(),
      reader: context.read<ChainReader>(),
      createdPolls: context.read<CreatedPollsStore>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = context.watch<AppState>().capabilities;
    return FutureBuilder<RelayOrganizerPort>(
      future: _port,
      builder: (context, snapshot) {
        final port = snapshot.data;
        if (port == null) {
          // One quiet frame while the bundled module ABIs load (they can
          // only be missing in a broken build).
          return const Scaffold(
            body: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Db.mute,
                ),
              ),
            ),
          );
        }
        return OrganizeSpaceView(
          port: port,
          nfcAvailable: capabilities.hasNfc,
          onCreate: () => context.go('/organize/create'),
          onRunEvent: (pollAddress) =>
              context.pushOnce('/live/$pollAddress/host'),
        );
      },
    );
  }
}
