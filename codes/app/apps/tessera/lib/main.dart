import 'package:core_chain/config.dart';
import 'package:core_crypto/proof/proof_service_factory.dart';
import 'package:core_domain/voting/ranked_irv.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/identity_store.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/format.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

void main() => runApp(const TesseraApp());

class TesseraApp extends StatelessWidget {
  const TesseraApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Tessera',
        debugShowCheckedModeBanner: false,
        theme: buildDarkBauhausTheme(),
        home: const ShellPlaceholderScreen(),
      );
}

/// R1 placeholder shell — exists only to prove the workspace composes: every
/// core package below is imported and exercised at runtime. The real
/// three-space IA (VOTE / ORGANIZE / JOIN / You) arrives in R3 on top of the
/// R2 journey engine; nothing here survives that.
class ShellPlaceholderScreen extends StatelessWidget {
  const ShellPlaceholderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Touch each package so a wiring regression is a compile/runtime failure,
    // not a silent omission.
    final relay = RelayClient(baseUrl: AppConfig.relayerUrl);
    final wired = <(String, String)>[
      ('core_domain', 'ranked IRV ready - up to $kMaxRankedOptions options'),
      ('core_chain', 'registry ${shortAddr(AppConfig.registryAddress)}'),
      (
        'core_crypto',
        proofServiceAvailable
            ? 'prover available on this platform'
            : 'prover not available here (honest capability copy lands in R2)',
      ),
      ('core_relay', 'relayer ${relay.baseUrl}'),
      (
        'core_storage',
        'seed generator ok: ${generateIdentitySeed().length == 66}',
      ),
      ('design_system', 'Dark Bauhaus tokens loaded'),
    ];

    return Scaffold(
      body: DotGridBackground(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                Text('TESSERA', style: dbSans(34, 800, Db.chalk)),
                const SizedBox(height: 4),
                Text(
                  'REVOLUTION SHELL - R1 (WORKSPACE EXTRACTION)',
                  style: dbMono(11, Db.segnale),
                ),
                const SizedBox(height: 24),
                Container(
                  decoration: BoxDecoration(
                    color: Db.slate,
                    border: Border.all(color: Db.rule),
                  ),
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final (name, status) in wired) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                width: 150,
                                child: Text(name, style: dbMono(12, Db.chalk)),
                              ),
                              Expanded(
                                child: Text(status, style: dbMono(11, Db.mute)),
                              ),
                            ],
                          ),
                        ),
                        if (name != 'design_system')
                          const Divider(color: Db.ruleSoft, height: 1),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Features land in R2+ (journey engine, three-space IA). '
                  'codes/mobile remains the working reference until cutover.',
                  style: dbSans(13, 400, Db.chalkDim),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
