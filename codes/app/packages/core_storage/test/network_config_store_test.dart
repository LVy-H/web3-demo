import 'package:flutter_test/flutter_test.dart';
import 'package:core_chain/config.dart';
import 'package:core_storage/network_config_store.dart';

const _valid = NetworkConfig(
  rpcUrl: 'https://rpc.example.com',
  relayerUrl: 'https://relayer.example.com',
  registryAddress: '0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9',
  semaphoreAddress: '0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0',
  chainId: 11155111,
);

void main() {
  // AppConfig network fields are process-global; never leave them overridden.
  tearDown(() => AppConfig.apply(null));

  group('InMemoryNetworkConfigStore', () {
    test('load is null until something is saved', () async {
      final s = InMemoryNetworkConfigStore();
      expect(await s.load(), isNull);
    });

    test('save then load round-trips the config', () async {
      final s = InMemoryNetworkConfigStore();
      await s.save(_valid);
      expect(await s.load(), _valid);
    });

    test('clear removes the override', () async {
      final s = InMemoryNetworkConfigStore(_valid);
      expect(await s.load(), _valid);
      await s.clear();
      expect(await s.load(), isNull);
    });
  });

  group('NetworkConfig JSON', () {
    test('toJson/fromJson round-trip', () {
      expect(NetworkConfig.fromJson(_valid.toJson()), _valid);
    });

    test(
      'fromJson tolerates missing/garbage fields (falls back to defaults)',
      () {
        final d = AppConfig.defaults;
        final c = NetworkConfig.fromJson({
          'rpcUrl': 'https://only-rpc.example',
        });
        expect(c.rpcUrl, 'https://only-rpc.example');
        expect(c.relayerUrl, d.relayerUrl);
        expect(c.registryAddress, d.registryAddress);
        expect(c.chainId, d.chainId);
      },
    );

    test('fromJson accepts a stringified chainId', () {
      expect(NetworkConfig.fromJson({'chainId': '42'}).chainId, 42);
    });
  });

  group('format validation (the brick guard)', () {
    test('a well-formed config is valid', () {
      expect(_valid.isValidFormat, isTrue);
      expect(AppConfig.defaults.isValidFormat, isTrue);
    });

    test('a non-http URL is rejected', () {
      expect(_valid.copyWith(rpcUrl: 'notaurl').isValidFormat, isFalse);
      expect(_valid.copyWith(relayerUrl: 'ftp://x').isValidFormat, isFalse);
      expect(_valid.copyWith(rpcUrl: '').isValidFormat, isFalse);
    });

    test('a malformed address is rejected', () {
      expect(_valid.copyWith(registryAddress: '0x123').isValidFormat, isFalse);
      expect(
        _valid.copyWith(semaphoreAddress: 'not-an-address').isValidFormat,
        isFalse,
      );
    });

    test('a non-positive chainId is rejected', () {
      expect(_valid.copyWith(chainId: 0).isValidFormat, isFalse);
      expect(_valid.copyWith(chainId: -1).isValidFormat, isFalse);
    });

    test('isAddress / isHttpUrl edge cases', () {
      expect(
        NetworkConfig.isAddress(' 0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9 '),
        isTrue,
      );
      expect(
        NetworkConfig.isAddress('0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc'),
        isFalse,
      );
      expect(NetworkConfig.isHttpUrl('http://localhost:8545'), isTrue);
      expect(NetworkConfig.isHttpUrl('https://x.io/path'), isTrue);
      expect(NetworkConfig.isHttpUrl('://nohost'), isFalse);
    });
  });

  group('AppConfig overlay', () {
    test('defaults: no override → not overridden, effective == defaults', () {
      expect(AppConfig.isOverridden, isFalse);
      expect(AppConfig.effective, AppConfig.defaults);
    });

    test('apply(config) updates the effective statics + flags overridden', () {
      AppConfig.apply(_valid);
      expect(AppConfig.rpcUrl, _valid.rpcUrl);
      expect(AppConfig.relayerUrl, _valid.relayerUrl);
      expect(AppConfig.registryAddress, _valid.registryAddress);
      expect(AppConfig.semaphoreAddress, _valid.semaphoreAddress);
      expect(AppConfig.chainId, _valid.chainId);
      expect(AppConfig.effective, _valid);
      expect(AppConfig.isOverridden, isTrue);
    });

    test('apply(null) resets to defaults', () {
      AppConfig.apply(_valid);
      AppConfig.apply(null);
      expect(AppConfig.effective, AppConfig.defaults);
      expect(AppConfig.isOverridden, isFalse);
    });
  });
}
