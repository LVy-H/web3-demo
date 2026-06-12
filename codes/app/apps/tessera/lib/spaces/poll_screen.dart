// R3 replaces this file with the real journey-state poll surface (one route,
// rendered by voter/blind journey state). The router and the module
// resolution below do not change when it does — only this file's rendering.
import 'package:design_system/theme.dart';
import 'package:flutter/material.dart';

import '../routing/poll_module_resolver.dart';
import 'space_placeholder.dart';

/// The single `/poll/:address` surface. The module type is resolved ON-CHAIN
/// via [PollModuleResolver] — never from a `?module=` query hint — so the
/// legacy "card tap shows the wrong ballot" bug class is structurally
/// impossible. Unknown/unreachable addresses render typed error states with
/// an exit, never a crash.
class PollScreen extends StatefulWidget {
  final String address;
  final PollModuleResolver resolver;

  const PollScreen({super.key, required this.address, required this.resolver});

  @override
  State<PollScreen> createState() => _PollScreenState();
}

class _PollScreenState extends State<PollScreen> {
  late Future<PollModuleResolution> _resolution;

  @override
  void initState() {
    super.initState();
    _resolution = widget.resolver.resolve(widget.address);
  }

  void _retry() {
    setState(() => _resolution = widget.resolver.resolve(widget.address));
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<PollModuleResolution>(
    future: _resolution,
    builder: (context, snapshot) {
      final resolution = snapshot.data;
      if (resolution == null) {
        return SpacePlaceholder(
          title: 'POLL',
          caption: 'Resolving on-chain…',
          showBack: true,
          children: const [
            Center(child: CircularProgressIndicator(color: Db.segnale)),
          ],
        );
      }
      return switch (resolution) {
        PollModuleResolved(:final info, :final moduleType) => SpacePlaceholder(
          title: info.title.isEmpty ? 'POLL' : info.title,
          caption: 'Poll surface — R3 placeholder',
          showBack: true,
          children: [
            PlaceholderRow(label: 'address', value: widget.address),
            PlaceholderRow(label: 'module', value: moduleType),
            const SizedBox(height: 12),
            Text(
              'The journey-state ballot for this module lands here '
              'in R3 — rendered from the on-chain module type above, '
              'never from a link hint.',
              style: dbSans(13, 400, Db.chalkDim),
            ),
          ],
        ),
        PollUnknown(:final messageKey) => SpacePlaceholder(
          title: 'POLL NOT FOUND',
          caption: messageKey,
          showBack: true,
          children: [
            PlaceholderRow(label: 'address', value: widget.address),
            const SizedBox(height: 12),
            Text(
              'This address is not a poll in the registry. Check the '
              'link or code you followed.',
              style: dbSans(13, 400, Db.chalkDim),
            ),
          ],
        ),
        PollLookupFailed(:final messageKey) => SpacePlaceholder(
          title: 'CAN’T REACH THE NETWORK',
          caption: messageKey,
          showBack: true,
          children: [
            PlaceholderRow(label: 'address', value: widget.address),
            const SizedBox(height: 12),
            Text(
              'The poll registry could not be reached. Retry when you '
              'are back online.',
              style: dbSans(13, 400, Db.chalkDim),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: _retry,
                child: const Text('RETRY'),
              ),
            ),
          ],
        ),
      };
    },
  );
}
