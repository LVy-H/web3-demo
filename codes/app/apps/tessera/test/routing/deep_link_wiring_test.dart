// Wiring test: a cold-start OS link injected into TesseraApp drives the REAL
// router to the matching screen — proving the bridge is actually connected in
// the app, not just unit-correct in isolation. A fake source keeps it off the
// platform channel.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tessera/app.dart';
import 'package:tessera/routing/deep_link_service.dart';
import 'package:tessera/spaces/poll_screen.dart';
import 'package:tessera/spaces/vote_space_screen.dart';
import 'package:tessera/spaces/you_verify_screen.dart';

import '../test_dependencies.dart';

class _FakeSource implements DeepLinkSource {
  _FakeSource({this.initial});
  final Uri? initial;
  final StreamController<Uri> _controller = StreamController<Uri>.broadcast();
  void emit(Uri uri) => _controller.add(uri);
  @override
  Future<Uri?> initialLink() async => initial;
  @override
  Stream<Uri> linkStream() => _controller.stream;
}

const _addr = '0x1111111111111111111111111111111111111111';

void main() {
  testWidgets(
    'cold-start link drives the real router via the initial-link path '
    '(verify link → Verify surface; network-free, so deterministic)',
    (tester) async {
      final deps = await buildTestDependencies();
      await tester.pumpWidget(
        TesseraApp(
          dependencies: deps,
          deepLinkSource: _FakeSource(initial: Uri.parse('tessera://verify')),
        ),
      );
      await tester.pumpAndSettle();
      // The shell's VOTE home reads known polls from real secure storage with
      // a 3s timeout; with no platform under test that timer is still armed.
      // Advance past it (the store's catch makes the TimeoutException a no-op)
      // so teardown sees no pending timer.
      await tester.pump(const Duration(seconds: 4));

      expect(find.byType(YouVerifyScreen), findsOneWidget);
    },
  );

  testWidgets('a warm link navigates after the app is already running', (
    tester,
  ) async {
    final source = _FakeSource();
    final deps = await buildTestDependencies(
      fetchPolls: () async => [testPollInfo(_addr, 'ranked-vote')],
    );
    await tester.pumpWidget(
      TesseraApp(dependencies: deps, deepLinkSource: source),
    );
    await tester.pumpAndSettle();
    // No initial link → the voter home is showing.
    expect(find.byType(VoteSpaceScreen), findsOneWidget);

    source.emit(Uri.parse('tessera://poll/$_addr'));
    await tester.pumpAndSettle();

    expect(find.byType(PollScreen), findsOneWidget);
  });

  testWidgets('no source injected → deep linking is simply off (home shows)', (
    tester,
  ) async {
    final deps = await buildTestDependencies();
    await tester.pumpWidget(TesseraApp(dependencies: deps));
    await tester.pumpAndSettle();

    expect(find.byType(VoteSpaceScreen), findsOneWidget);
  });
}
