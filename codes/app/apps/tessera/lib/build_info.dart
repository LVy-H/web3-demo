// Build-time version stamp.
//
// The release pipeline (.github/workflows/release.yml) injects the git tag at
// build time:
//
//   flutter build <target> --release \
//     --build-name=${TAG#v} \
//     --dart-define=TESSERA_BUILD_VERSION=$TAG
//
// `--build-name` feeds the platform package metadata (Android versionName
// etc.); the dart-define feeds the in-app About screen (YOU → Settings →
// About) without a runtime plugin. Local/dev builds don't set it, so the
// About screen keeps hiding the row — exactly the pre-existing behavior.
const String? tesseraBuildVersion =
    bool.hasEnvironment('TESSERA_BUILD_VERSION')
    ? String.fromEnvironment('TESSERA_BUILD_VERSION')
    : null;
