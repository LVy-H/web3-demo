import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/data/repositories/verify_repository.dart';
import 'package:tessera/ui/features/verify/verify_view_model.dart';

class FakeVerifyRepo implements VerifyRepository {
  final bool? used;
  final Object? error;
  FakeVerifyRepo({this.used, this.error});
  @override
  Future<bool> isNullifierUsed(String pollAddress, String nullifier) async {
    if (error != null) throw error!;
    return used ?? false;
  }
}

const poll = '0x1111111111111111111111111111111111111111';

void main() {
  test('verified when the nullifier is used', () async {
    final vm = VerifyViewModel(FakeVerifyRepo(used: true));
    await vm.verify(poll, '12345');
    expect(vm.verdict, VerifyVerdict.verified);
  });

  test('not found when the nullifier is unused', () async {
    final vm = VerifyViewModel(FakeVerifyRepo(used: false));
    await vm.verify(poll, '12345');
    expect(vm.verdict, VerifyVerdict.notFound);
  });

  test('error on invalid poll address (no chain call)', () async {
    final vm = VerifyViewModel(FakeVerifyRepo(used: true));
    await vm.verify('0xabc', '12345');
    expect(vm.verdict, VerifyVerdict.error);
    expect(vm.error, contains('poll'));
  });

  test('error on non-decimal nullifier', () async {
    final vm = VerifyViewModel(FakeVerifyRepo(used: true));
    await vm.verify(poll, 'deadbeef');
    expect(vm.verdict, VerifyVerdict.error);
    expect(vm.error, contains('nullifier'));
  });

  test('error when the read throws', () async {
    final vm = VerifyViewModel(FakeVerifyRepo(error: Exception('rpc down')));
    await vm.verify(poll, '12345');
    expect(vm.verdict, VerifyVerdict.error);
  });
}
