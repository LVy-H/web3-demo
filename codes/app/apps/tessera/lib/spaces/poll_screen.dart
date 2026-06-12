// The single `/poll/:address` surface (R3): module type resolved ON-CHAIN
// via [PollModuleResolver] — never a `?module=` hint — then rendered as the
// matching journey's current state by feature_vote. The router and the
// resolver did not change; only this file's rendering did.
import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/chain_writer.dart';
import 'package:core_chain/config.dart';
import 'package:core_crypto/proof/proof_service.dart';
import 'package:core_domain/journeys/blind_journey.dart';
import 'package:core_domain/journeys/capabilities.dart';
import 'package:core_domain/journeys/voter_journey.dart';
import 'package:core_relay/relay_client.dart';
import 'package:core_storage/blind_commit_store.dart';
import 'package:core_storage/identity_store.dart';
import 'package:design_system/theme.dart';
import 'package:feature_vote/feature_vote.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../routing/poll_module_resolver.dart';
import '../routing/safe_navigation.dart';
import '../state/app_state.dart';
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
        PollModuleResolved(:final info, :final moduleType) => _resolved(
          moduleType,
          info.title,
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

  Widget _resolved(String moduleType, String title) {
    final module = voterModuleFor(moduleType);
    if (module != null) {
      return _VoterPollHost(
        address: widget.address,
        module: module,
        moduleType: moduleType,
        title: title,
      );
    }
    if (moduleType == 'blind-vote') {
      return _BlindPollHost(address: widget.address, title: title);
    }
    if (moduleType == 'live-vote') {
      return SpacePlaceholder(
        title: title.isEmpty ? 'LIVE VOTE' : title,
        caption: 'A live, in-the-room vote',
        showBack: true,
        children: [
          Text(
            'This vote runs live, in the room. Join it with the invite '
            'the host is showing.',
            style: dbSans(13, 400, Db.chalkDim),
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton(
              onPressed: () => context.pushOnce('/live/${widget.address}/vote'),
              child: const Text('OPEN THE LIVE VOTE'),
            ),
          ),
        ],
      );
    }
    return SpacePlaceholder(
      title: title.isEmpty ? 'POLL' : title,
      caption: 'This vote type isn’t supported yet',
      showBack: true,
      children: [
        Text(
          'This vote uses a newer format this app version doesn’t '
          'understand yet. Update the app to take part.',
          style: dbSans(13, 400, Db.chalkDim),
        ),
      ],
    );
  }
}

/// Hosts the proof-module journey: builds the production port adapter over
/// the provided core services, owns the machine's lifecycle, and renders the
/// feature_vote journey screen.
class _VoterPollHost extends StatefulWidget {
  final String address;
  final VoterModule module;
  final String moduleType;
  final String title;

  const _VoterPollHost({
    required this.address,
    required this.module,
    required this.moduleType,
    required this.title,
  });

  @override
  State<_VoterPollHost> createState() => _VoterPollHostState();
}

class _VoterPollHostState extends State<_VoterPollHost> {
  late AppState _appState;
  late Capabilities _capabilities;
  late VoterJourneyMachine _machine;

  @override
  void initState() {
    super.initState();
    _appState = context.read<AppState>();
    _capabilities = _appState.capabilities;
    _machine = _buildMachine();
    _appState.addListener(_onAppState);
  }

  VoterJourneyMachine _buildMachine() {
    final chainReader = context.read<ChainReader>();
    final policyReader = ResultsPolicyReader(client: chainReader.client);
    return VoterJourneyMachine(
      capabilities: _capabilities,
      port: VoterPortAdapter(
        reader: chainReader,
        relay: context.read<RelayClient>(),
        proofService: context.read<ProofService>(),
        identityStore: context.read<IdentityStore>(),
        pollAddress: widget.address,
        module: widget.module,
        readResultsPolicy: () => policyReader.read(widget.address),
        knownPolls: SecureKnownPollsStore(),
        pollTitle: widget.title,
        moduleType: widget.moduleType,
      ),
    );
  }

  /// Capabilities refine asynchronously at startup (relayer probe). The
  /// machine snapshots them at construction, so while the journey is still
  /// in a re-derivable early state, rebuild it with the fresh surface —
  /// otherwise "ASK TO JOIN" could stay disabled on a stale probing reason.
  void _onAppState() {
    if (!mounted || _appState.capabilities == _capabilities) return;
    final early = switch (_machine.state) {
      VoterLoading() ||
      VoterLoadFailed() ||
      VoterEligibilityChecking() ||
      VoterNotEligible() ||
      VoterWaitingForOpen() => true,
      _ => false,
    };
    if (!early) return;
    setState(() {
      _capabilities = _appState.capabilities;
      _machine.dispose();
      _machine = _buildMachine();
    });
  }

  @override
  void dispose() {
    _appState.removeListener(_onAppState);
    _machine.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surveyReader = widget.module == VoterModule.survey
        ? SurveyReader(
            reader: context.read<ChainReader>(),
            pollAddress: widget.address,
          )
        : null;
    return PollJourneyScreen(
      key: ObjectKey(_machine),
      machine: _machine,
      title: widget.title,
      kindLabel: voteKindLabel(widget.moduleType),
      loadSurveyDetails: surveyReader?.load,
      loadSurveyResults: surveyReader == null
          ? null
          : () => surveyReader.load(withResults: true),
      // /you/verify renders on the ROOT navigator (router.dart), so this
      // push layers the focused verify page over the poll — pushing a page
      // INSIDE the shell from here would clone a second shell and trip
      // Navigator's duplicate page-key assertion.
      onVerifyReceipt: (code) => context.pushOnce(
        '/you/verify?poll=${widget.address}&nullifier=$code',
      ),
      // The YOU space itself is a shell branch — switching to it is a tab
      // switch (`go`), never a push (same duplicate-shell crash).
      onOpenIdentity: () => context.go('/you'),
    );
  }
}

/// Hosts the sealed-until-reveal journey. Its writes are voter-addressed, so
/// it needs a local signer; without one the screen says so honestly instead
/// of offering actions that would fail.
class _BlindPollHost extends StatefulWidget {
  final String address;
  final String title;

  const _BlindPollHost({required this.address, required this.title});

  @override
  State<_BlindPollHost> createState() => _BlindPollHostState();
}

class _BlindPollHostState extends State<_BlindPollHost> {
  ChainWriter? _writer;
  BlindJourneyMachine? _machine;
  late Future<String?> _abi;

  @override
  void initState() {
    super.initState();
    _abi = _loadAbi();
  }

  Future<String?> _loadAbi() async {
    if (AppConfig.devPrivateKey.isEmpty) return null;
    // core_chain's packaged copy: register/commitVote/revealVote are
    // unchanged by R4, so the pre-R4 ABI is correct for these writes.
    return rootBundle.loadString(
      'packages/core_chain/assets/abi/ZkBlindVoting.json',
    );
  }

  BlindJourneyMachine _machineFor(String abiJson) {
    final existing = _machine;
    if (existing != null) return existing;
    final writer = _writer ??= ChainWriter(
      rpcUrl: AppConfig.rpcUrl,
      chainId: AppConfig.chainId,
      privateKey: AppConfig.devPrivateKey,
    );
    final machine = BlindJourneyMachine(
      port: BlindPortAdapter(
        reader: context.read<ChainReader>(),
        writer: writer,
        commitStore: context.read<BlindCommitStore>(),
        pollAddress: widget.address,
        blindAbiJson: abiJson,
        knownPolls: SecureKnownPollsStore(),
        pollTitle: widget.title,
      ),
    );
    _machine = machine;
    return machine;
  }

  @override
  void dispose() {
    _machine?.dispose();
    _writer?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final chainReader = context.read<ChainReader>();
    return FutureBuilder<String?>(
      future: _abi,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return SpacePlaceholder(
            title: widget.title.isEmpty ? 'POLL' : widget.title,
            caption: 'Loading…',
            showBack: true,
            children: const [
              Center(child: CircularProgressIndicator(color: Db.segnale)),
            ],
          );
        }
        final abiJson = snap.data;
        if (abiJson == null) {
          return SpacePlaceholder(
            title: widget.title.isEmpty ? 'POLL' : widget.title,
            caption: 'Not on this device yet',
            showBack: true,
            children: [
              Text(
                'This sealed-until-reveal vote can’t be cast from this '
                'device yet — it needs a build that can send its own '
                'transactions. Use the web app for now.',
                style: dbSans(13, 400, Db.chalkDim),
              ),
            ],
          );
        }
        return BlindJourneyScreen(
          machine: _machineFor(abiJson),
          title: widget.title,
          loadOptions: () => chainReader.getOptions(widget.address),
          loadTally: () async => (
            await chainReader.getOptions(widget.address),
            await chainReader.getResults(widget.address),
          ),
        );
      },
    );
  }
}
