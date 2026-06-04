import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../config.dart';
import '../../../data/services/app_reload.dart';
import '../../../data/services/network_config_store.dart';
import '../../core/dot_grid_background.dart';
import '../../core/theme.dart';

/// Point the app at your own backend without a rebuild. The same hosted build
/// (e.g. on Cloudflare Pages) can target any chain/relayer/registry: edit here,
/// save, and the change applies on the next load.
///
/// Persistence is via [NetworkConfigStore]; the values are re-read and applied
/// in `main()`, so saving here only writes + asks to reload (web) / restart
/// (native). We never mutate the live config in place — that would leave the
/// already-built reader/writer on the old chain while creators used the new
/// addresses.
class NetworkConfigScreen extends StatefulWidget {
  const NetworkConfigScreen({super.key});

  @override
  State<NetworkConfigScreen> createState() => _NetworkConfigScreenState();
}

class _NetworkConfigScreenState extends State<NetworkConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _rpc;
  late final TextEditingController _relayer;
  late final TextEditingController _registry;
  late final TextEditingController _semaphore;
  late final TextEditingController _chainId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final c = AppConfig.effective;
    _rpc = TextEditingController(text: c.rpcUrl);
    _relayer = TextEditingController(text: c.relayerUrl);
    _registry = TextEditingController(text: c.registryAddress);
    _semaphore = TextEditingController(text: c.semaphoreAddress);
    _chainId = TextEditingController(text: c.chainId.toString());
  }

  @override
  void dispose() {
    _rpc.dispose();
    _relayer.dispose();
    _registry.dispose();
    _semaphore.dispose();
    _chainId.dispose();
    super.dispose();
  }

  String? _url(String? v) =>
      NetworkConfig.isHttpUrl(v ?? '') ? null : 'http(s) URL required';
  String? _addr(String? v) =>
      NetworkConfig.isAddress(v ?? '') ? null : '0x + 40 hex digits';
  String? _chain(String? v) =>
      (int.tryParse((v ?? '').trim()) ?? 0) > 0 ? null : 'positive integer';

  NetworkConfig _read() => NetworkConfig(
    rpcUrl: _rpc.text.trim(),
    relayerUrl: _relayer.text.trim(),
    registryAddress: _registry.text.trim(),
    semaphoreAddress: _semaphore.text.trim(),
    chainId: int.parse(_chainId.text.trim()),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    await context.read<NetworkConfigStore>().save(_read());
    if (mounted) await _applied('Custom backend saved.');
  }

  Future<void> _reset() async {
    setState(() => _busy = true);
    await context.read<NetworkConfigStore>().clear();
    if (mounted) await _applied('Reverted to the built-in defaults.');
  }

  /// Confirm the write and offer the apply step. Web can reload in place (which
  /// re-runs `main()` and re-applies); native must be restarted by the user.
  Future<void> _applied(String what) async {
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Db.slate,
        shape: const RoundedRectangleBorder(
          side: BorderSide(color: Db.rule),
        ),
        title: Text('SAVED', style: dbLabel(size: 11, tracking: 0.16)),
        content: Text(
          canReloadApp
              ? '$what\n\nReload now to apply it to this session.'
              : '$what\n\nRestart the app to apply it.',
          style: dbSans(14, 500, Db.chalkDim),
        ),
        actions: [
          if (canReloadApp) ...[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('LATER', style: dbSans(12, 700, Db.mute)),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                reloadApp();
              },
              child: Text('RELOAD NOW', style: dbSans(12, 800, Db.segnale)),
            ),
          ] else
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: dbSans(12, 800, Db.segnale)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => context.pop(),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Db.chalk,
                            size: 20,
                          ),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text('NETWORK', style: dbHero(40))),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Point this app at your own chain, relayer and registry. '
                      'The same build works against any backend — useful when '
                      'this is hosted (e.g. Cloudflare Pages) and the defaults '
                      'are localhost. Changes apply on reload.',
                      style: dbSans(13, 500, Db.chalkDim),
                    ),
                    const SizedBox(height: 4),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        AppConfig.isOverridden
                            ? 'Status: CUSTOM backend active'
                            : 'Status: using built-in defaults',
                        style: dbMono(11, Db.segnale),
                      ),
                    ),
                    const SizedBox(height: 22),
                    _field('RPC URL', _rpc, 'https://your-node.example', _url,
                        TextInputType.url),
                    _field('RELAYER URL', _relayer,
                        'https://your-relayer.example', _url, TextInputType.url),
                    _field('REGISTRY ADDRESS', _registry, '0x…', _addr,
                        TextInputType.text),
                    _field('SEMAPHORE VERIFIER ADDRESS', _semaphore, '0x…',
                        _addr, TextInputType.text),
                    _field('CHAIN ID', _chainId, 'e.g. 11155111 (Sepolia)',
                        _chain, TextInputType.number,
                        digitsOnly: true),
                    const SizedBox(height: 8),
                    _saveButton(),
                    const SizedBox(height: 12),
                    Center(
                      child: TextButton(
                        onPressed: _busy ? null : _reset,
                        child: Text(
                          'RESET TO DEFAULTS',
                          style: dbSans(12, 700, Db.mute, letterSpacing: 1.2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _saveButton() => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: _busy ? null : _save,
      style: FilledButton.styleFrom(
        backgroundColor: Db.segnale,
        disabledBackgroundColor: Db.slate,
        foregroundColor: Db.chalk,
        shape: const RoundedRectangleBorder(),
        padding: const EdgeInsets.symmetric(vertical: 16),
      ),
      child: Text(
        _busy
            ? 'SAVING…'
            : (canReloadApp ? 'SAVE & RELOAD' : 'SAVE — RESTART TO APPLY'),
        style: dbSans(13, 800, Db.chalk, letterSpacing: 1.4),
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController c,
    String hint,
    String? Function(String?) validator,
    TextInputType keyboard, {
    bool digitsOnly = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: dbLabel(size: 10, tracking: 0.16)),
        const SizedBox(height: 8),
        TextFormField(
          controller: c,
          keyboardType: keyboard,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          inputFormatters:
              digitsOnly ? [FilteringTextInputFormatter.digitsOnly] : null,
          validator: validator,
          style: dbMono(13, Db.chalk),
          cursorColor: Db.segnale,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Db.slate3,
            hintText: hint,
            hintStyle: dbSans(13, 400, Db.muteDim),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Db.rule),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.zero,
              borderSide: BorderSide(color: Db.segnale),
            ),
            errorStyle: dbSans(11, 600, Db.segnale),
          ),
        ),
      ],
    ),
  );
}
