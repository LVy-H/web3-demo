import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/services/proof_service.dart';
import '../../../data/services/proof_service_factory.dart';
import '../../core/dot_grid_background.dart';
import '../../core/theme.dart';
import 'identity_view_model.dart';

/// Manage the single app identity seed — create, import, reveal/copy, or clear.
/// The seed is the only secret a recurring member needs to cast anonymous votes,
/// so it never leaves the device unless the user explicitly copies it.
class IdentityScreen extends StatefulWidget {
  const IdentityScreen({super.key});

  @override
  State<IdentityScreen> createState() => _IdentityScreenState();
}

class _IdentityScreenState extends State<IdentityScreen> {
  final _import = TextEditingController();
  bool _revealed = false;

  // The Semaphore commitment derived from the current seed (decimal string),
  // shown so the user can hand it to an organizer to be registered. Only
  // derivable where a prover is available (web now); null elsewhere/while
  // computing. Keyed by [_commitmentSeed] so we re-derive when the seed changes.
  String? _commitment;
  String? _commitmentSeed;

  @override
  void dispose() {
    _import.dispose();
    super.dispose();
  }

  // Derive the commitment for [seed] once per distinct seed, post-frame and
  // mounted-guarded. No-op when proving isn't available on this platform.
  void _ensureCommitment(String seed) {
    if (!proofServiceAvailable || seed == _commitmentSeed) return;
    _commitmentSeed = seed;
    _commitment = null;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final proof = context.read<ProofService>();
      try {
        final c = await proof.deriveCommitment(seed);
        if (mounted && seed == _commitmentSeed) {
          setState(() => _commitment = c);
        }
      } catch (_) {
        // Leave it null — the commitment panel just won't render.
      }
    });
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(m, style: dbMono(12, Db.chalk)),
        backgroundColor: Db.slate,
      ));

  static String _mask(String s) => s.length <= 16
      ? s
      : '${s.substring(0, 10)} …… ${s.substring(s.length - 6)}';

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<IdentityViewModel>();
    if (vm.hasIdentity) _ensureCommitment(vm.seed!);
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text('IDENTITY', style: dbHero(48)),
                  const SizedBox(height: 10),
                  Text(
                    'Your Semaphore identity seed. Hold it to vote anonymously '
                    'across polls — anyone with this seed can vote as you, so '
                    'keep it secret.',
                    style: dbSans(13, 400, Db.chalkDim, height: 1.5),
                  ),
                  const SizedBox(height: 22),
                  if (vm.loading)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Db.segnale),
                        ),
                      ),
                    )
                  else ...[
                    _statusPanel(vm),
                    const SizedBox(height: 22),
                    if (vm.hasIdentity) ...[
                      _seedPanel(vm.seed!),
                      if (_commitment != null) ...[
                        const SizedBox(height: 18),
                        _commitmentPanel(_commitment!),
                      ],
                      const SizedBox(height: 18),
                      _dangerButton('CLEAR IDENTITY', () async {
                        final vm = context.read<IdentityViewModel>();
                        await vm.clear();
                        if (!mounted) return;
                        setState(() => _revealed = false);
                        if (vm.error == null) _snack('Identity cleared.');
                      }),
                    ] else
                      _createButton(),
                    const SizedBox(height: 28),
                    _importSection(),
                    if (vm.error != null) ...[
                      const SizedBox(height: 16),
                      Text(vm.error!, style: dbMono(11, Db.amber, height: 1.5)),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPanel(IdentityViewModel vm) {
    final ok = vm.hasIdentity;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Db.slate,
        border: Border(
            left: BorderSide(color: ok ? Db.success : Db.segnale, width: 3)),
      ),
      child: Row(children: [
        Icon(ok ? Icons.fingerprint : Icons.person_off_outlined,
            size: 18, color: ok ? Db.success : Db.segnale),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            ok ? 'Identity ready' : 'No identity yet',
            style: dbSans(14, 700, Db.chalk),
          ),
        ),
      ]),
    );
  }

  Widget _seedPanel(String seed) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Db.slate3,
          border: Border.fromBorderSide(BorderSide(color: Db.rule)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('SEED', style: dbLabel(size: 10, tracking: 0.16)),
          const SizedBox(height: 10),
          SelectableText(
            _revealed ? seed : _mask(seed),
            style: dbMono(13, Db.chalk, height: 1.5),
          ),
          const SizedBox(height: 14),
          Row(children: [
            _miniButton(
              _revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
              _revealed ? 'HIDE' : 'REVEAL',
              () => setState(() => _revealed = !_revealed),
            ),
            const SizedBox(width: 10),
            _miniButton(Icons.copy_outlined, 'COPY', () {
              Clipboard.setData(ClipboardData(text: seed));
              _snack('Seed copied to clipboard.');
            }),
          ]),
        ]),
      );

  Widget _commitmentPanel(String commitment) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Db.slate3,
          border: Border.fromBorderSide(BorderSide(color: Db.rule)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('COMMITMENT (give this to an organizer to register you)',
              style: dbLabel(size: 10, tracking: 0.16)),
          const SizedBox(height: 10),
          SelectableText(commitment, style: dbMono(13, Db.chalk, height: 1.5)),
          const SizedBox(height: 14),
          Row(children: [
            _miniButton(Icons.copy_outlined, 'COPY', () {
              Clipboard.setData(ClipboardData(text: commitment));
              _snack('Commitment copied to clipboard.');
            }),
          ]),
        ]),
      );

  Widget _miniButton(IconData icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Db.void_,
            border: Border.fromBorderSide(BorderSide(color: Db.rule)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: Db.chalkDim),
            const SizedBox(width: 7),
            Text(label, style: dbLabel(size: 10, color: Db.chalkDim)),
          ]),
        ),
      );

  Widget _createButton() => SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: () async {
            final vm = context.read<IdentityViewModel>();
            await vm.createNew();
            if (!mounted) return;
            if (vm.error == null) _snack('New identity created.');
          },
          style: FilledButton.styleFrom(
            backgroundColor: Db.segnale,
            foregroundColor: Db.chalk,
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: Text('CREATE NEW IDENTITY',
              style: dbSans(13, 800, Db.chalk, letterSpacing: 1.4)),
        ),
      );

  Widget _dangerButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: Db.amber,
            side: BorderSide(color: Db.rule),
            shape: const RoundedRectangleBorder(),
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(label,
              style: dbLabel(size: 11, color: Db.amber, tracking: 0.16)),
        ),
      );

  Widget _importSection() =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('IMPORT SEED / INVITE TOKEN',
            style: dbLabel(size: 10, tracking: 0.16)),
        const SizedBox(height: 10),
        TextField(
          controller: _import,
          style: dbMono(13, Db.chalk),
          cursorColor: Db.segnale,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Db.slate3,
            hintText: 'Paste an existing seed or organizer invite token',
            hintStyle: dbMono(12, Db.muteDim),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.rule)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.zero,
                borderSide: BorderSide(color: Db.segnale)),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () async {
              final vm = context.read<IdentityViewModel>();
              final ok = await vm.import(_import.text);
              if (!mounted) return;
              if (ok && vm.error == null) {
                _import.clear();
                setState(() => _revealed = false);
                _snack('Identity imported.');
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: Db.chalk,
              side: BorderSide(color: Db.rule),
              shape: const RoundedRectangleBorder(),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: Text('IMPORT',
                style: dbLabel(size: 11, color: Db.chalk, tracking: 0.16)),
          ),
        ),
      ]);
}
