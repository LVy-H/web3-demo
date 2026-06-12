import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../widgets/you_widgets.dart';
import 'voting_pass_controller.dart';

/// The voting pass surface (spec §4.1 "You" + §3 principle 5): create,
/// import, back up and remove the pass — never the words "Semaphore",
/// "identity" or "commitment" in primary copy. The registration code lives
/// under an expandable ADVANCED section for the manual-registration path.
class VotingPassSection extends StatefulWidget {
  final VotingPassController controller;
  const VotingPassSection({super.key, required this.controller});

  @override
  State<VotingPassSection> createState() => _VotingPassSectionState();
}

class _VotingPassSectionState extends State<VotingPassSection> {
  final _importField = TextEditingController();
  bool _importOpen = false;
  bool _backupOpen = false;
  bool _advancedOpen = false;

  VotingPassController get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onChanged);
  }

  @override
  void didUpdateWidget(VotingPassSection old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  @override
  void dispose() {
    _c.removeListener(_onChanged);
    _importField.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  static String _mask(String s) => s.length <= 16
      ? '••••••••'
      : '${s.substring(0, 6)} •••••••• ${s.substring(s.length - 4)}';

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const YouSectionLabel('VOTING PASS'),
        const SizedBox(height: 8),
        if (_c.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Db.segnale,
                ),
              ),
            ),
          )
        else ...[
          _statusPanel(),
          const SizedBox(height: 14),
          if (_c.hasPass) ..._passActions() else ..._noPassActions(),
          const SizedBox(height: 6),
          _importExpander(),
          if (_c.hasPass) _advancedExpander(),
          if (_c.error != null) ...[
            const SizedBox(height: 10),
            Text(_c.error!, style: dbMono(11, Db.amber, height: 1.5)),
          ],
        ],
      ],
    );
  }

  Widget _statusPanel() {
    final ok = _c.hasPass;
    return YouAccentPanel(
      accent: ok ? Db.success : Db.mute,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                ok ? Icons.verified_user_outlined : Icons.badge_outlined,
                size: 18,
                color: ok ? Db.success : Db.mute,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  ok ? 'Active on this device' : 'No pass yet',
                  style: dbSans(14, 700, Db.chalk),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ok
                ? 'Your voting pass lets you vote anonymously. It stays on '
                      'this device unless you back it up.'
                : 'A voting pass lets you vote anonymously. You don’t need '
                      'one to browse polls or check receipts — create one '
                      'now, or it’s set up for you the first time you vote.',
            style: dbSans(13, 400, Db.chalkDim, height: 1.5),
          ),
        ],
      ),
    );
  }

  List<Widget> _noPassActions() => [
    YouPrimaryButton(
      label: _c.busy ? 'CREATING…' : 'CREATE PASS',
      busy: _c.busy,
      onTap: () async {
        final ok = await _c.create();
        if (!mounted) return;
        if (ok) showYouSnack(context, 'Voting pass created. Back it up below.');
      },
    ),
  ];

  List<Widget> _passActions() => [
    YouOutlineButton(
      label: _backupOpen ? 'HIDE BACKUP' : 'BACK UP PASS',
      onTap: () => setState(() => _backupOpen = !_backupOpen),
    ),
    if (_backupOpen) ...[const SizedBox(height: 10), _backupPanel()],
    const SizedBox(height: 10),
    YouOutlineButton(
      label: 'REMOVE FROM THIS DEVICE',
      color: Db.amber,
      onTap: _c.busy ? null : _confirmRemove,
    ),
  ];

  Widget _backupPanel() => YouFramedPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_amber_outlined, size: 15, color: Db.amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Treat this like a password — anyone who has it can vote '
                'as you.',
                style: dbSans(12, 600, Db.amber, height: 1.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SelectableText(_c.seed!, style: dbMono(13, Db.chalk, height: 1.5)),
        const SizedBox(height: 14),
        Row(
          children: [
            YouMiniButton(
              icon: Icons.copy_outlined,
              label: 'COPY',
              onTap: () {
                Clipboard.setData(ClipboardData(text: _c.seed!));
                showYouSnack(
                  context,
                  'Pass copied — store it somewhere safe, like a password '
                  'manager.',
                );
              },
            ),
          ],
        ),
      ],
    ),
  );

  Widget _importExpander() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      YouExpanderHeader(
        label: _c.hasPass ? 'IMPORT A DIFFERENT PASS' : 'IMPORT A PASS',
        open: _importOpen,
        onTap: () => setState(() => _importOpen = !_importOpen),
      ),
      if (_importOpen) ...[
        if (_c.hasPass)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Importing replaces the pass on this device. Back up the '
              'current one first if you still need it.',
              style: dbSans(12, 500, Db.amber, height: 1.4),
            ),
          ),
        YouTextField(
          label: 'YOUR PASS',
          controller: _importField,
          hint: 'Paste a pass you backed up',
        ),
        const SizedBox(height: 10),
        YouOutlineButton(
          label: _c.busy ? 'IMPORTING…' : 'IMPORT',
          onTap: _c.busy
              ? null
              : () async {
                  final ok = await _c.importPass(_importField.text);
                  if (!mounted) return;
                  if (ok) {
                    _importField.clear();
                    setState(() {
                      _importOpen = false;
                      _backupOpen = false;
                    });
                    showYouSnack(context, 'Pass imported.');
                  }
                },
        ),
        const SizedBox(height: 6),
      ],
    ],
  );

  Widget _advancedExpander() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      YouExpanderHeader(
        label: 'ADVANCED',
        open: _advancedOpen,
        onTap: () {
          setState(() => _advancedOpen = !_advancedOpen);
          if (_advancedOpen) _c.ensureRegistrationCode();
        },
      ),
      if (_advancedOpen) ...[
        _registrationCodePanel(),
        const SizedBox(height: 6),
      ],
    ],
  );

  Widget _registrationCodePanel() => YouFramedPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const YouSectionLabel('REGISTRATION CODE'),
        const SizedBox(height: 6),
        Text(
          'Give this to an organizer to register you manually.',
          style: dbSans(12, 500, Db.chalkDim, height: 1.4),
        ),
        const SizedBox(height: 12),
        if (!_c.canDeriveRegistrationCode)
          Text(
            'Not available on this device yet — open the app in a browser '
            'to see your registration code.',
            style: dbMono(11, Db.mute, height: 1.5),
          )
        else if (_c.derivingCode)
          Text('Working it out…', style: dbMono(11, Db.mute))
        else if (_c.registrationCode == null)
          Text(
            'Couldn’t work out the code right now — try again later.',
            style: dbMono(11, Db.mute, height: 1.5),
          )
        else ...[
          SelectableText(
            _c.registrationCode!,
            style: dbMono(13, Db.chalk, height: 1.5),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              YouMiniButton(
                icon: Icons.copy_outlined,
                label: 'COPY',
                onTap: () {
                  Clipboard.setData(ClipboardData(text: _c.registrationCode!));
                  showYouSnack(context, 'Registration code copied.');
                },
              ),
            ],
          ),
        ],
      ],
    ),
  );

  Future<void> _confirmRemove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Db.slate,
        shape: const RoundedRectangleBorder(side: BorderSide(color: Db.rule)),
        title: Text('REMOVE PASS?', style: dbLabel(size: 11, tracking: 0.16)),
        content: Text(
          'If you haven’t backed it up, you’ll permanently lose the ability '
          'to vote anywhere this pass is registered. (Your pass is masked '
          'here for safety: ${_mask(_c.seed ?? '')})',
          style: dbSans(14, 500, Db.chalkDim, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('CANCEL', style: dbSans(12, 700, Db.mute)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('REMOVE', style: dbSans(12, 800, Db.segnale)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final ok = await _c.remove();
    if (!mounted) return;
    if (ok) {
      setState(() {
        _backupOpen = false;
        _advancedOpen = false;
      });
      showYouSnack(context, 'Pass removed from this device.');
    }
  }
}
