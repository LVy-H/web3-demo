import 'package:flutter_test/flutter_test.dart';
import 'package:zkvote_mobile/data/services/identity_store.dart';
import 'package:zkvote_mobile/ui/features/identity/identity_view_model.dart';

void main() {
  test('load against an empty store -> no identity, not loading', () async {
    final vm = IdentityViewModel(InMemoryIdentityStore());
    await vm.load();
    expect(vm.hasIdentity, isFalse);
    expect(vm.loading, isFalse);
  });

  test('load surfaces an existing seed', () async {
    final vm = IdentityViewModel(InMemoryIdentityStore('0xdead'));
    await vm.load();
    expect(vm.hasIdentity, isTrue);
    expect(vm.seed, '0xdead');
  });

  test('createNew persists a fresh seed and sets hasIdentity', () async {
    final store = InMemoryIdentityStore();
    final vm = IdentityViewModel(store);
    await vm.load();
    await vm.createNew();
    expect(vm.hasIdentity, isTrue);
    expect(vm.seed, matches(RegExp(r'^0x[0-9a-f]{64}$')));
    expect(await store.read(), vm.seed);
  });

  test('import trims, rejects blank, accepts a token', () async {
    final store = InMemoryIdentityStore();
    final vm = IdentityViewModel(store);
    await vm.load();
    expect(await vm.import('   '), isFalse);
    expect(vm.hasIdentity, isFalse);
    expect(await vm.import('  invite-token-42 '), isTrue);
    expect(vm.seed, 'invite-token-42');
    expect(await store.read(), 'invite-token-42');
  });

  test('clear removes the identity from store and memory', () async {
    final store = InMemoryIdentityStore('seed');
    final vm = IdentityViewModel(store);
    await vm.load();
    expect(vm.hasIdentity, isTrue);
    await vm.clear();
    expect(vm.hasIdentity, isFalse);
    expect(await store.read(), isNull);
  });
}
