import 'package:feature_you/feature_you.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package wires into the workspace', () {
    expect(featureYouPackageName, 'feature_you');
  });
}
