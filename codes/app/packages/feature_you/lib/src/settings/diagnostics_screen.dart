import 'dart:async';

import 'package:core_chain/config.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/you_widgets.dart';

/// Honest per-platform copy for "can this device prepare a vote?" (spec
/// §4.3). Pure so the matrix is unit-testable.
String provingStatusCopy({
  required bool canProve,
  required bool isWeb,
  required TargetPlatform platform,
}) {
  if (canProve) {
    return isWeb
        ? 'Available — your vote is prepared right in this browser.'
        : 'Available on this device.';
  }
  final where = switch (platform) {
    TargetPlatform.iOS => 'iPhones and iPads',
    TargetPlatform.android => 'this Android build',
    TargetPlatform.linux ||
    TargetPlatform.macOS ||
    TargetPlatform.windows => 'desktop builds',
    _ => 'this device',
  };
  return 'Not available on $where yet — open the poll link in a browser to '
      'vote. You can still browse polls, check receipts and organize from '
      'here.';
}

enum ProbeStatus { checking, ok, unreachable }

/// Read-only health panel: is the chain RPC answering, is the relayer
/// answering, and can this device prepare votes. The probes are injected
/// (production: a registry read and the relayer info endpoint) so tests
/// never touch the network.
class DiagnosticsScreen extends StatefulWidget {
  final Future<bool> Function() checkChain;
  final Future<bool> Function() checkRelayer;
  final bool canProve;

  const DiagnosticsScreen({
    super.key,
    required this.checkChain,
    required this.checkRelayer,
    required this.canProve,
  });

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  ProbeStatus _chain = ProbeStatus.checking;
  ProbeStatus _relayer = ProbeStatus.checking;
  int _runId = 0; // discard results of a superseded run

  @override
  void initState() {
    super.initState();
    _runProbes();
  }

  Future<void> _runProbes() async {
    final run = ++_runId;
    setState(() {
      _chain = ProbeStatus.checking;
      _relayer = ProbeStatus.checking;
    });
    // Probes run concurrently; each lands independently. The injected
    // checks are expected not to throw, but a throw still degrades to
    // "unreachable" rather than an error screen.
    unawaited(
      widget.checkChain().then((ok) => ok).catchError((_) => false).then((ok) {
        if (mounted && run == _runId) {
          setState(
            () => _chain = ok ? ProbeStatus.ok : ProbeStatus.unreachable,
          );
        }
      }),
    );
    unawaited(
      widget.checkRelayer().then((ok) => ok).catchError((_) => false).then((
        ok,
      ) {
        if (mounted && run == _runId) {
          setState(
            () => _relayer = ok ? ProbeStatus.ok : ProbeStatus.unreachable,
          );
        }
      }),
    );
  }

  static String _host(String url) => Uri.tryParse(url)?.host ?? url;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('DIAGNOSTICS', style: dbHero(40)),
                  const SizedBox(height: 8),
                  Text(
                    'What this device can reach and do right now.',
                    style: dbSans(13, 500, Db.chalkDim),
                  ),
                  const SizedBox(height: 22),
                  const YouSectionLabel('CONNECTIONS'),
                  const SizedBox(height: 8),
                  YouRowsPanel(
                    rows: [
                      _probeRow('Chain (RPC)', _host(AppConfig.rpcUrl), _chain),
                      const Divider(
                        height: 1,
                        thickness: 1,
                        color: Db.ruleSoft,
                      ),
                      _probeRow(
                        'Relayer',
                        _host(AppConfig.relayerUrl),
                        _relayer,
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const YouSectionLabel('VOTING FROM THIS DEVICE'),
                  const SizedBox(height: 8),
                  YouAccentPanel(
                    accent: widget.canProve ? Db.success : Db.amber,
                    child: Text(
                      provingStatusCopy(
                        canProve: widget.canProve,
                        isWeb: kIsWeb,
                        platform: defaultTargetPlatform,
                      ),
                      style: dbSans(13, 500, Db.chalkDim, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 18),
                  YouOutlineButton(
                    label: 'RUN CHECKS AGAIN',
                    onTap: _runProbes,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _probeRow(String label, String host, ProbeStatus status) {
    final (color, text) = switch (status) {
      ProbeStatus.checking => (Db.mute, 'CHECKING…'),
      ProbeStatus.ok => (Db.success, 'REACHABLE'),
      ProbeStatus.unreachable => (Db.segnale, 'UNREACHABLE'),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Flexible(
            child: Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: dbSans(13, 600, Db.chalkDim),
            ),
          ),
          const SizedBox(width: 12),
          const Spacer(),
          Flexible(
            child: Text(
              host,
              overflow: TextOverflow.ellipsis,
              style: dbMono(11, Db.mute),
            ),
          ),
          const SizedBox(width: 10),
          Text(text, style: dbMono(11, color)),
        ],
      ),
    );
  }
}
