import 'package:feature_organize/feature_organize.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('package wires into the workspace', () {
    expect(featureOrganizePackageName, 'feature_organize');
  });
}
