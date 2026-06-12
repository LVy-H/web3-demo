// R3: the real run-event console (the organizer dashboard's "run event"
// mode). Thin glue only — builds the sponsored live-host port from the DI
// graph and delegates to feature_organize's [LiveHostConsole], driven by
// the liveHost journey machine. The router did not change; only this file
// did (R2f contract).
import 'package:core_chain/chain_reader.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/org_key_store.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'organize_wire.dart';

class LiveHostScreen extends StatefulWidget {
  final String address;

  const LiveHostScreen({super.key, required this.address});

  @override
  State<LiveHostScreen> createState() => _LiveHostScreenState();
}

class _LiveHostScreenState extends State<LiveHostScreen> {
  RelayLiveHostPort? _port;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _port ??= RelayLiveHostPort(
      relay: context.read<RelayClient>(),
      reader: context.read<ChainReader>(),
      orgKeys: context.read<OrgKeyStore>(),
      gateway: HttpOrganizeRelayGateway(),
      pollAddress: widget.address,
    );
  }

  @override
  Widget build(BuildContext context) =>
      LiveHostConsole(port: _port!, onExit: () => context.go('/organize'));
}
