{
  description = "Anonymous Lottery and Voting System";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      supportedSystems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      # Android SDK components are unfree and license-gated; opt in here so
      # composeAndroidPackages can build a usable, patched SDK.
      nixpkgsFor = forAllSystems (system: import nixpkgs {
        inherit system;
        config = {
          allowUnfree = true;
          android_sdk.accept_license = true;
        };
      });
    in {
      devShells = forAllSystems (system:
        let
          pkgs = nixpkgsFor.${system};
          inherit (pkgs) lib;
          isLinux = pkgs.stdenv.hostPlatform.isLinux;

          # A Nix-patched Android SDK: aapt2 / sdkmanager / adb are patchelf'd so
          # they actually run on NixOS. Every version defaults to "latest",
          # resolved against the pinned nixpkgs, so we never hard-pin a
          # build-tools / NDK / platform number that might be absent in this rev.
          androidComposition = pkgs.androidenv.composeAndroidPackages {
            includeNDK = true;
            includeEmulator = true;
            includeSystemImages = true;
            systemImageTypes = [ "google_apis_playstore" ];
            abiVersions = [ "x86_64" ]; # x86_64 image -> KVM-accelerated emulator
          };
          androidSdk = androidComposition.androidsdk;
          sdkRoot = "${androidSdk}/libexec/android-sdk";
        in {
          default = pkgs.mkShell ({
            buildInputs = with pkgs; [
              nodejs_22 # existing web3 / frontend toolchain
              flutter   # bundles the Dart SDK (>= 3.9 provides `dart mcp-server`)
            ] ++ lib.optionals isLinux [
              chromium  # flutter web target -> CHROME_EXECUTABLE
              jdk17     # Android Gradle Plugin 8.x requires JDK 17
              androidSdk
              # Linux desktop target (`flutter build linux`) build deps
              pkg-config
              cmake
              ninja
              clang
              gtk3
              glib
            ];
          } // lib.optionalAttrs isLinux {
            CHROME_EXECUTABLE = "${pkgs.chromium}/bin/chromium";
            JAVA_HOME = pkgs.jdk17.home;
            ANDROID_HOME = sdkRoot;
            ANDROID_SDK_ROOT = sdkRoot;

            shellHook = ''
              # NDK lives at a versioned path under the SDK; expose it for Gradle.
              export ANDROID_NDK_ROOT="$(ls -d "$ANDROID_SDK_ROOT"/ndk/* 2>/dev/null | head -n1)"
              export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"

              # Force Gradle to use the Nix-patched aapt2 instead of the
              # dynamically-linked one it downloads from Maven (which won't run
              # on NixOS).
              _aapt2="$(ls "$ANDROID_SDK_ROOT"/build-tools/*/aapt2 2>/dev/null | head -n1)"
              if [ -n "$_aapt2" ]; then
                export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=$_aapt2 ''${GRADLE_OPTS:-}"
              fi

              echo "🟦 Flutter devShell ready — Android SDK at $ANDROID_SDK_ROOT"
              echo "   sanity check: flutter doctor -v"
            '';
          });
        }
      );
    };
}
