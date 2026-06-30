import 'package:core_chain/config.dart';
import 'package:core_storage/network_config_store.dart';
import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_reload.dart';

/// Point the app at your own backend without a rebuild (lifted from the
/// legacy network_config_screen over core_storage's [NetworkConfigStore]).
///
/// The saved backend override is applied in exactly one place — startup, via
/// `AppConfig.apply` in the DI composition root. Saving a backend URL change
/// persists + asks to reload (web) / restart (native); saving only the convener
/// token applies immediately because the token intentionally lives in memory.
/// [onConfigChanged] is R2f's re-probe hook (AppState.refreshCapabilities) so
/// the capability surface re-evaluates immediately after a save.
class NetworkSettingsScreen extends StatefulWidget {
  final NetworkConfigStore store;
  final Future<void> Function() onConfigChanged;

  const NetworkSettingsScreen({
    super.key,
    required this.store,
    required this.onConfigChanged,
  });

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _rpc;
  late final TextEditingController _relayer;
  late final TextEditingController _server;
  late final TextEditingController _convenerToken;
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
    _server = TextEditingController(text: c.serverUrl);
    _convenerToken = TextEditingController(text: AppConfig.convenerToken ?? '');
    _registry = TextEditingController(text: c.registryAddress);
    _semaphore = TextEditingController(text: c.semaphoreAddress);
    _chainId = TextEditingController(text: c.chainId.toString());
  }

  @override
  void dispose() {
    _rpc.dispose();
    _relayer.dispose();
    _server.dispose();
    _convenerToken.dispose();
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
    serverUrl: _server.text.trim(),
    registryAddress: _registry.text.trim(),
    semaphoreAddress: _semaphore.text.trim(),
    chainId: int.parse(_chainId.text.trim()),
  );

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final config = _read();
    // The convener Bearer token is a credential, not a backend pointer — it
    // lives in-memory only (re-pasted after a restart), set here so the demo
    // operator can paste the admin token the server prints on startup.
    final token = _convenerToken.text.trim();
    AppConfig.convenerToken = token.isEmpty ? null : token;
    await _persist(
      () => widget.store.save(config),
      config == AppConfig.effective
          ? 'Admin token saved for this session.'
          : 'Custom backend saved.',
      reloadRequired: config != AppConfig.effective,
    );
  }

  Future<void> _reset() async => _persist(
    () => widget.store.clear(),
    'Reverted to the built-in defaults.',
    reloadRequired: true,
  );

  /// Run a store write with the busy spinner, then re-probe capabilities and
  /// offer the apply step. Any failure resets the button (never a stuck
  /// "SAVING…") and surfaces the error, so a misconfiguration can't look
  /// like a silent hang.
  Future<void> _persist(
    Future<void> Function() write,
    String done, {
    required bool reloadRequired,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await write();
      // R2f re-probe hook: refresh the capability surface now. A failing
      // probe must not turn a successful save into an error.
      try {
        await widget.onConfigChanged();
      } catch (_) {}
      if (mounted) await _applied(done, reloadRequired: reloadRequired);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: Db.slate,
            content: Text(
              'Could not save: $e',
              style: dbSans(13, 600, Db.chalk),
            ),
          ),
        );
      }
    }
  }

  /// Confirm the write and offer the apply step only when backend settings
  /// changed. The admin token is intentionally in-memory; reloading would clear
  /// it, so token-only saves show an OK dialog instead.
  Future<void> _applied(String what, {required bool reloadRequired}) async {
    setState(() => _busy = false);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Db.slate,
        shape: const RoundedRectangleBorder(side: BorderSide(color: Db.rule)),
        title: Text('SAVED', style: dbLabel(size: 11, tracking: 0.16)),
        content: Text(
          reloadRequired
              ? (canReloadApp
                    ? '$what\n\nReload now to apply the backend settings.'
                    : '$what\n\nRestart the app to apply the backend settings.')
              : '$what\n\nYou can create and manage decisions now. Reloading '
                    'clears this in-memory token.',
          style: dbSans(14, 500, Db.chalkDim),
        ),
        actions: [
          if (!reloadRequired)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text('OK', style: dbSans(12, 800, Db.segnale)),
            )
          else if (canReloadApp) ...[
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
      appBar: AppBar(backgroundColor: Colors.transparent),
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
                    Text('NETWORK', style: dbHero(40)),
                    const SizedBox(height: 8),
                    Text(
                      'Point this app at a Tessera server. Paste the convener '
                      'token to create and manage decisions. Backend URL '
                      'changes apply on reload; the token applies immediately.',
                      style: dbSans(13, 500, Db.chalkDim),
                    ),
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
                    _field(
                      'RPC URL',
                      _rpc,
                      'https://your-node.example',
                      _url,
                      TextInputType.url,
                    ),
                    _field(
                      'RELAYER URL',
                      _relayer,
                      'https://your-relayer.example',
                      _url,
                      TextInputType.url,
                    ),
                    _field(
                      'SERVER URL (open-ballot)',
                      _server,
                      'http://127.0.0.1:3001',
                      _url,
                      TextInputType.url,
                    ),
                    _field(
                      'CONVENER TOKEN (admin)',
                      _convenerToken,
                      'paste the token the server prints on startup',
                      null,
                      TextInputType.text,
                    ),
                    _field(
                      'REGISTRY ADDRESS',
                      _registry,
                      '0x…',
                      _addr,
                      TextInputType.text,
                    ),
                    _field(
                      'SEMAPHORE VERIFIER ADDRESS',
                      _semaphore,
                      '0x…',
                      _addr,
                      TextInputType.text,
                    ),
                    _field(
                      'CHAIN ID',
                      _chainId,
                      'e.g. 11155111 (Sepolia)',
                      _chain,
                      TextInputType.number,
                      digitsOnly: true,
                    ),
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
        _busy ? 'SAVING…' : 'SAVE',
        style: dbSans(13, 800, Db.chalk, letterSpacing: 1.4),
      ),
    ),
  );

  Widget _field(
    String label,
    TextEditingController c,
    String hint,
    String? Function(String?)? validator,
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
          inputFormatters: digitsOnly
              ? [FilteringTextInputFormatter.digitsOnly]
              : null,
          validator: validator,
          style: dbMono(13, Db.chalk),
          cursorColor: Db.segnale,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: Db.slate3,
            hintText: hint,
            hintStyle: dbSans(13, 400, Db.muteDim),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
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
