// ORGANIZE-space wire glue (R3). The relayer calls the organize feature
// needs BEYOND core_relay's typed client (R4 create-poll policy fields, the
// sponsored start-voting lifecycle route — PR #108) live here, in app-shell
// territory, because the R3 fan-out freezes every pubspec and core package:
// the shell already depends on `http`, the feature package does not.
//
// Shared by the organize*/live_host* glue screens only. NOT a DI change:
// these objects are built inside the owned screens from the existing
// providers; router/guards/composition root stay untouched.
import 'dart:convert';

import 'package:core_chain/chain_reader.dart';
import 'package:core_chain/config.dart' show AppConfig;
import 'package:core_relay/relay_client.dart'
    show CreatePollResult, RelayClient;
import 'package:core_storage/created_polls_store.dart';
import 'package:feature_organize/feature_organize.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;

/// Production [OrganizeRelayGateway] over the relayer's HTTP surface.
///
/// `create-poll` carries the spec §5 policy choices as the optional
/// top-level `visibility` / `resultsPolicy` fields; `initData` stays the
/// PRE-R4 initialize encoding (the relayer appends the trailing policy
/// argument server-side — re-encoding client-side would double it).
class HttpOrganizeRelayGateway implements OrganizeRelayGateway {
  final http.Client _client;

  /// Read lazily so a saved network change (YOU → network settings) applies
  /// without rebuilding the gateway.
  final String Function() _baseUrl;

  /// Creates include an on-chain transaction; match RelayClient's slow lane.
  final Duration timeout;

  HttpOrganizeRelayGateway({
    String Function()? baseUrl,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  }) : _baseUrl = baseUrl ?? (() => AppConfig.relayerUrl),
       _client = client ?? http.Client();

  @override
  Future<CreatePollResult> createPoll({
    required String moduleType,
    required String title,
    required String description,
    required String initDataHex,
    required int visibility,
    required int resultsPolicy,
  }) async {
    final data = await _post(
      '/api/relay/create-poll',
      {
        'moduleType': moduleType,
        'title': title,
        'description': description,
        'initData': initDataHex,
        'visibility': visibility,
        'resultsPolicy': resultsPolicy,
      },
      failure: 'The poll could not be created. Try again.',
    );
    final pollAddress = data['pollAddress'];
    if (pollAddress is! String || pollAddress.isEmpty) {
      throw const OrganizeWireException(
        'The poll could not be created. Try again.',
      );
    }
    return CreatePollResult(
      pollAddress: pollAddress,
      txHash: data['txHash'] is String ? data['txHash'] as String : null,
    );
  }

  @override
  Future<void> startVoting(String pollAddress) async {
    await _post(
      '/api/relay/start-voting',
      {'pollAddress': pollAddress},
      failure: 'Voting could not be started. Try again.',
    );
  }

  @override
  Future<void> endVoting(String pollAddress) async {
    // The deployed relayer has no sponsored close route yet (its create/
    // start lifecycle landed in PR #108; close did not). Honest copy, not a
    // raw 404 — the dashboard shows this verbatim.
    throw const OrganizeWireException(
      'Closing a poll from this device isn’t available yet — the '
      'sponsoring service doesn’t support it. This is coming in an update.',
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body, {
    required String failure,
  }) async {
    http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse('${_baseUrl()}$path'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } catch (_) {
      throw const OrganizeWireException(
        'The sponsoring service didn’t answer. Check the connection and '
        'try again.',
      );
    }
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(response.body);
      data = decoded is Map<String, dynamic> ? decoded : <String, dynamic>{};
    } catch (_) {
      data = <String, dynamic>{};
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // The relayer's `error` field is written for end users (validation
      // copy); surface it when present, fall back to our own copy.
      final serverError = data['error'];
      throw OrganizeWireException(
        serverError is String && serverError.isNotEmpty ? serverError : failure,
      );
    }
    return data;
  }
}

/// Builds the production [RelayOrganizerPort] for the organize screens:
/// gateway + module-initialize ABIs from core_chain's bundled package
/// assets (the same copies the DI root loads for [ChainReader]).
Future<RelayOrganizerPort> buildOrganizerPort({
  required RelayClient relay,
  required ChainReader reader,
  required CreatedPollsStore createdPolls,
}) async {
  const pkgAbi = 'packages/core_chain/assets/abi';
  final anonAbi = await rootBundle.loadString('$pkgAbi/ZkAnonVoting.json');
  final surveyAbi = await rootBundle.loadString('$pkgAbi/ZkSurveyVoting.json');
  return RelayOrganizerPort(
    relay: relay,
    reader: reader,
    gateway: HttpOrganizeRelayGateway(),
    createdPolls: createdPolls,
    flatModuleAbiJson: _abiArray(anonAbi),
    surveyVotingAbiJson: _abiArray(surveyAbi),
  );
}

/// Hardhat artifacts wrap the ABI as `{"abi": [...]}`; the encoders want
/// the bare array string (mirrors the DI root's unwrap).
String _abiArray(String artifactJson) {
  final decoded = jsonDecode(artifactJson);
  return jsonEncode(decoded is Map ? decoded['abi'] : decoded);
}
