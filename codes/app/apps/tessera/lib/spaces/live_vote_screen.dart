// Live-voter flow (R3): scanned ticket → joining → pending (big code) →
// admitted → ballot → proving → done, driven by core_domain's
// LiveVoterMachine. This screen owns the machine's lifecycle and wires the
// production RelayLiveVoterPort from the DI graph; the rendering lives in
// feature_join's LiveVoterFlow. The route stays guarded by canProve
// (routing/guards.dart) — this screen never renders on a device that
// cannot cast.
import 'dart:async';

import 'package:core_chain/chain_reader.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_domain/journeys/live_journeys.dart';
import 'package:core_relay/relay_client.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:feature_join/live.dart';
import 'package:feature_join/ui.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';

class LiveVoteScreen extends StatefulWidget {
  final String address;
  final String? ticket;

  /// Test seam: builds the journey machine (fake port + manual ticker in
  /// tests). Production (null) wires [RelayLiveVoterPort] from the DI graph.
  final LiveVoterMachine Function(BuildContext context)? machineBuilder;

  /// Test seam: records locations instead of driving the real router.
  final void Function(BuildContext context, String location)? navigateOverride;

  /// Test seam forwarded to [LiveVoterFlow]'s ticket scanner.
  final Future<String?> Function(BuildContext context)? scanTicket;

  const LiveVoteScreen({
    super.key,
    required this.address,
    this.ticket,
    this.machineBuilder,
    this.navigateOverride,
    this.scanTicket,
  });

  @override
  State<LiveVoteScreen> createState() => _LiveVoteScreenState();
}

class _LiveVoteScreenState extends State<LiveVoteScreen> {
  late final LiveVoterMachine _machine;

  @override
  void initState() {
    super.initState();
    _machine = (widget.machineBuilder ?? _productionMachine)(context);
    final ticket = widget.ticket;
    if (ticket != null && ticket.trim().isNotEmpty) {
      // A deep link arrived with the ticket already scanned: enter the
      // journey immediately (needsTicket → joining). Legal from the
      // machine's initial state by construction.
      unawaited(_machine.advance(LiveTicketProvided(ticket)));
    }
  }

  LiveVoterMachine _productionMachine(BuildContext context) {
    final reader = context.read<ChainReader>();
    final port = RelayLiveVoterPort(
      pollAddress: widget.address,
      relay: context.read<RelayClient>(),
      proofService: context.read<ProofService>(),
      fetchGroup: reader.getRegisteredCommitments,
      fetchOptions: reader.getOptions,
      fetchPhase: reader.getState,
    );
    return LiveVoterMachine(
      port: port,
      ticker: const SystemLiveTicker(),
      capabilities: context.read<AppState>().capabilities,
    );
  }

  @override
  void dispose() {
    _machine.dispose(); // cancels any in-flight effect + the pending cadence
    super.dispose();
  }

  void _navigate(String location) {
    final navigate = widget.navigateOverride;
    if (navigate != null) {
      navigate(context, location);
    } else {
      context.go(location);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text('LIVE SESSION', style: dbLabel(size: 11, tracking: 0.16)),
      ),
      body: DotGridBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                LiveVoterFlow(
                  machine: _machine,
                  navigate: _navigate,
                  scanTicket: widget.scanTicket,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
