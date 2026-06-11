import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:wallet/wallet.dart' show EthereumAddress; // web3dart 3.x moved it here
import 'package:web3dart/web3dart.dart';

/// Signs and broadcasts write transactions with a local private key.
///
/// This is a LOCAL-DEV signing path: a phone wallet (WalletConnect) cannot reach
/// the host-local Hardhat node, so M2 commit-reveal votes could never *land* on
/// desktop without it. When no key is configured, [canSign] is false and the UI
/// gates write actions (same posture as "connect a wallet"). NEVER ship a real
/// build with `DEV_PRIVATE_KEY` set.
class ChainWriter {
  final Web3Client _client;
  final EthPrivateKey? _creds;
  final int chainId;

  ChainWriter({
    required String rpcUrl,
    required this.chainId,
    String privateKey = '',
    http.Client? httpClient,
  })  : _client = Web3Client(rpcUrl, httpClient ?? http.Client()),
        _creds = privateKey.isEmpty
            ? null
            : EthPrivateKey.fromHex(_strip0x(privateKey));

  static String _strip0x(String s) => s.startsWith('0x') ? s.substring(2) : s;

  bool get canSign => _creds != null;
  String? get signerAddress => _creds?.address.eip55With0x;

  // Serializes sends so two concurrent callers on this shared signer can't fetch
  // the same nonce (which would drop/replace one tx).
  Future<void> _queue = Future<void>.value();

  /// Encode + sign + send a contract call, wait for the receipt, return the tx
  /// hash. Throws if the tx reverts or no signer is configured. Calls are
  /// serialized per [ChainWriter] to avoid nonce races.
  Future<String> send({
    required String to,
    required String abiJson,
    required String abiName,
    required String function,
    List<dynamic> params = const [],
  }) {
    final completer = Completer<String>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await _doSend(
            to: to,
            abiJson: abiJson,
            abiName: abiName,
            function: function,
            params: params));
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  Future<String> _doSend({
    required String to,
    required String abiJson,
    required String abiName,
    required String function,
    List<dynamic> params = const [],
  }) async {
    final creds = _creds;
    if (creds == null) {
      throw StateError('No dev signer configured (set DEV_PRIVATE_KEY).');
    }
    final contract = DeployedContract(
        ContractAbi.fromJson(abiJson, abiName), EthereumAddress.fromHex(to));
    final hash = await _client.sendTransaction(
      creds,
      Transaction.callContract(
        contract: contract,
        function: contract.function(function),
        parameters: params,
      ),
      chainId: chainId,
    );
    await _awaitReceipt(hash);
    return hash;
  }

  Future<TransactionReceipt> _awaitReceipt(
    String hash, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final r = await _client.getTransactionReceipt(hash);
      if (r != null) {
        if (r.status == false) throw Exception('Transaction reverted: $hash');
        return r;
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    throw Exception('Timed out waiting for receipt: $hash');
  }

  void dispose() => _client.dispose();
}
