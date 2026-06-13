import 'package:design_system/dot_grid_background.dart';
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import '../widgets/you_widgets.dart';
import 'verify_controller.dart';

/// The Verify surface: poll address + receipt code → "counted" / "not
/// found", jargon-free. Deep-linkable (`/you/verify?poll=…&nullifier=…`):
/// when both values are pre-filled the check runs automatically. Works
/// without a voting pass — checking a receipt is a public, read-only act.
class VerifyView extends StatefulWidget {
  final String? initialPollAddress;
  final String? initialReceiptCode;
  final ReceiptCheck checkReceipt;
  final PollTitleLookup? lookupPollTitle;

  const VerifyView({
    super.key,
    required this.checkReceipt,
    this.lookupPollTitle,
    this.initialPollAddress,
    this.initialReceiptCode,
  });

  @override
  State<VerifyView> createState() => _VerifyViewState();
}

class _VerifyViewState extends State<VerifyView> {
  late final VerifyController _controller = VerifyController(
    checkReceipt: widget.checkReceipt,
    lookupPollTitle: widget.lookupPollTitle,
  );
  late final _poll = TextEditingController(
    text: widget.initialPollAddress ?? '',
  );
  late final _code = TextEditingController(
    text: widget.initialReceiptCode ?? '',
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    if ((widget.initialPollAddress ?? '').isNotEmpty &&
        (widget.initialReceiptCode ?? '').isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _run());
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _poll.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _run() => _controller.verify(_poll.text, _code.text);

  @override
  Widget build(BuildContext context) {
    final checking = _controller.verdict == VerifyVerdict.checking;
    return Scaffold(
      appBar: AppBar(backgroundColor: Colors.transparent),
      body: DotGridBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('VERIFY', style: dbHero(48)),
                    const SizedBox(height: 10),
                    Text(
                      'Check that a receipt was counted — without revealing '
                      'who voted or what they chose. Anyone can check a '
                      'receipt; no voting pass needed.',
                      style: dbSans(14, 400, Db.chalkDim, height: 1.6),
                    ),
                    const SizedBox(height: 24),
                    YouTextField(
                      label: 'POLL ADDRESS',
                      controller: _poll,
                      hint: '0x…',
                    ),
                    const SizedBox(height: 16),
                    YouTextField(
                      label: 'RECEIPT CODE',
                      controller: _code,
                      hint: 'the long number on the receipt',
                    ),
                    const SizedBox(height: 18),
                    YouPrimaryButton(
                      label: checking ? 'CHECKING…' : 'CHECK RECEIPT',
                      busy: checking,
                      onTap: _run,
                    ),
                    const SizedBox(height: 20),
                    _verdict(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _verdict() {
    switch (_controller.verdict) {
      case VerifyVerdict.idle:
        return const SizedBox.shrink();
      case VerifyVerdict.checking:
        return const Center(
          child: Padding(
            padding: EdgeInsets.only(top: 8),
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Db.segnale,
              ),
            ),
          ),
        );
      case VerifyVerdict.counted:
        final title = _controller.pollTitle;
        return _panel(
          Db.success,
          Icons.verified_outlined,
          'COUNTED',
          title != null && title.isNotEmpty
              ? 'This receipt is counted in “$title”. It doesn’t reveal who '
                    'voted or what they chose.'
              : 'This receipt is counted in this poll. It doesn’t reveal who '
                    'voted or what they chose.',
        );
      case VerifyVerdict.notFound:
        return _panel(
          Db.mute,
          Icons.help_outline,
          'NOT FOUND',
          'Not found — this receipt isn’t recorded in this poll. Check the '
              'poll address and receipt code, then try again.',
        );
      case VerifyVerdict.error:
        return _panel(
          Db.segnale,
          Icons.error_outline,
          'COULDN’T CHECK',
          _controller.error ?? 'Something went wrong — try again.',
        );
    }
  }

  Widget _panel(Color color, IconData icon, String title, String body) =>
      YouAccentPanel(
        accent: color,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                // The verdict is the answer to "was my vote counted?" — make
                // it a live-region header so a screen reader announces it the
                // moment the async check lands.
                Expanded(
                  child: Semantics(
                    liveRegion: true,
                    header: true,
                    child: Text(
                      title,
                      style: dbSans(13, 800, color, letterSpacing: 1.4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(body, style: dbSans(13, 500, Db.chalkDim, height: 1.5)),
          ],
        ),
      );
}
