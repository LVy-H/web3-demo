// R3: the real Verify surface. Thin glue — keeps the route's query-param
// prefill contract (?poll=&nullifier=) and delegates to feature_you's
// [VerifyView]. Read-only: works without a voting pass.
import 'package:core_chain/chain_reader.dart';
import 'package:feature_you/feature_you.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../routing/poll_module_resolver.dart';

class YouVerifyScreen extends StatelessWidget {
  final String? poll;
  final String? nullifier;

  const YouVerifyScreen({super.key, this.poll, this.nullifier});

  @override
  Widget build(BuildContext context) {
    final reader = context.read<ChainReader>();
    final resolver = context.read<PollModuleResolver>();
    return VerifyView(
      initialPollAddress: poll,
      initialReceiptCode: nullifier,
      // The public participation check (nullifier-used) — the receipt code
      // IS the nullifier, but only this wiring layer knows that word.
      checkReceipt: reader.isNullifierUsed,
      // Best-effort title for the "counted in <poll title>" copy; resolver
      // failures cost only the title, never the verdict.
      lookupPollTitle: (address) async {
        final resolution = await resolver.resolve(address);
        return resolution is PollModuleResolved ? resolution.info.title : null;
      },
    );
  }
}
