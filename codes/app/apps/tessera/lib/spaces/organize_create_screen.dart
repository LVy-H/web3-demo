// R3: the real create flow. Thin glue only — builds the relayer-backed
// organizer port, then delegates to feature_organize's [CreateFlowView]
// (sponsored creation as THE path; spec §4.3). The router did not change;
// only this file did (R2f contract).
//
// Guard policy: this route stays a PASS-THROUGH even when no signer path
// exists — the journey machine renders the disabled deploy with the honest
// why-not (`reason.organizer.noSignerPath`), instead of the router hiding
// the flow.
import 'package:core_chain/chain_reader.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/created_polls_store.dart';
import 'package:design_system/theme.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'organize_wire.dart';

class OrganizeCreateScreen extends StatefulWidget {
  const OrganizeCreateScreen({super.key});

  @override
  State<OrganizeCreateScreen> createState() => _OrganizeCreateScreenState();
}

class _OrganizeCreateScreenState extends State<OrganizeCreateScreen> {
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
    // read, not watch: the machine captures capabilities at creation; a
    // mid-flow probe change must not rebuild (and reset) the whole form.
    final capabilities = context.read<AppState>().capabilities;
    return FutureBuilder<RelayOrganizerPort>(
      future: _port,
      builder: (context, snapshot) {
        final port = snapshot.data;
        if (port == null) {
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
        return CreateFlowView(
          port: port,
          capabilities: capabilities,
          onDone: (_) => context.go('/organize'),
        );
      },
    );
  }
}
