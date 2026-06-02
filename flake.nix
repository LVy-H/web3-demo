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
            # Flutter's gradle plugin sets up an NDK/CMake build for the app
            # (native-assets infra) even with no native code. Ship a patched
            # CMake so that configure step finds one instead of trying to
            # auto-install the unrunnable prebuilt cmake;3.22.1. The app pins
            # this exact version via externalNativeBuild.cmake.version.
            cmakeVersions = [ "4.1.2" ];
            # Pin NDK + build-tools to EXACTLY what android/app/build.gradle.kts
            # hard-pins. Otherwise they float to the nixpkgs default; if that
            # drifts from the Gradle pins, Gradle tries to auto-install the
            # missing version into the read-only store and the build dies —
            # the exact failure this overlay exists to prevent.
            ndkVersions = [ "29.0.14206865" ];
            buildToolsVersions = [ "36.1.0" ];
          };
          androidSdk = androidComposition.androidsdk;
          sdkRoot = "${androidSdk}/libexec/android-sdk";
        in {
          default = pkgs.mkShell ({
            # Point the dart MCP server / dart-tooling-daemon at the Flutter SDK.
            # Under Nix, `dart` is a symlink to a standalone Dart SDK store path
            # *outside* the Flutter tree, so the server's "walk up from my own
            # binary" auto-detection fails. These env vars are the documented
            # override; "${pkgs.flutter}" resolves to the SDK root and tracks the
            # pinned version automatically.
            FLUTTER_ROOT = "${pkgs.flutter}";
            FLUTTER_SDK = "${pkgs.flutter}";

            buildInputs = with pkgs; [
              nodejs_22 # existing web3 / frontend toolchain
              flutter   # bundles the Dart SDK (>= 3.9 provides `dart mcp-server`)
              git       # flutter shells out to git for SDK / version checks
              unzip     # gradle + sdk tooling unpack archives
              jq        # dev-stack.sh parses deployed-addresses.json by key
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
              libsecret # flutter_secure_storage_linux (pulled in by reown) needs libsecret-1
            ];
          } // lib.optionalAttrs isLinux {
            CHROME_EXECUTABLE = "${pkgs.chromium}/bin/chromium";
            JAVA_HOME = pkgs.jdk17.home;
            ANDROID_HOME = sdkRoot;
            ANDROID_SDK_ROOT = sdkRoot;

            shellHook = ''
              # --- Writable Android SDK overlay --------------------------------
              # The Nix store SDK is read-only, but sdkmanager / avdmanager / the
              # Gradle Android plugin all want to write (license acks, .temp,
              # .knownPackages). Mirror the store SDK as a symlink farm under a
              # writable root, with `licenses/` a real seeded dir. Top-level
              # writes (.temp etc.) land on the real overlay root; the package
              # subtrees stay read-only symlinks into the store.
              _nix_sdk="$ANDROID_SDK_ROOT"
              asdk="''${ZK_ANDROID_OVERLAY:-$HOME/asdk}"
              if [ ! -L "$asdk/.nix-src" ] || [ "$(readlink "$asdk/.nix-src" 2>/dev/null)" != "$_nix_sdk" ]; then
                echo "🛠  (re)building writable Android SDK overlay at $asdk"
                rm -rf "$asdk"; mkdir -p "$asdk"
                for _e in "$_nix_sdk"/*; do ln -sfn "$_e" "$asdk/$(basename "$_e")"; done
                rm -f "$asdk/licenses"; mkdir -p "$asdk/licenses"
                [ -d "$_nix_sdk/licenses" ] && cp -f "$_nix_sdk"/licenses/* "$asdk/licenses/" 2>/dev/null || true
                # AGP / Flutter look up integer platform dirs (e.g. android-36),
                # but nixpkgs ships minor-versioned ones (android-36.1). Expose a
                # real platforms/ dir carrying both the real name and the
                # major-only alias so `compileSdk = 36` resolves.
                if [ -d "$_nix_sdk/platforms" ]; then
                  rm -f "$asdk/platforms"; mkdir -p "$asdk/platforms"
                  for _p in "$_nix_sdk"/platforms/*; do
                    _pb="$(basename "$_p")"; ln -sfn "$_p" "$asdk/platforms/$_pb"
                    case "$_pb" in android-*.*) ln -sfn "$_p" "$asdk/platforms/''${_pb%.*}";; esac
                  done
                fi
                # Some Flutter plugins (e.g. :jni, pulled in by reown) pin
                # `ndkVersion flutter.ndkVersion`, which resolves to an NDK
                # nixpkgs doesn't ship. nixpkgs has exactly one NDK; expose it
                # under its real name AND the requested alias, with a matching
                # source.properties so AGP's version check passes. The toolchain
                # is the patched store NDK — the thing that must actually run on
                # NixOS (a Google-downloaded NDK wouldn't).
                if [ -d "$_nix_sdk/ndk" ]; then
                  rm -f "$asdk/ndk"; mkdir -p "$asdk/ndk"
                  _realndk=""
                  for _n in "$_nix_sdk"/ndk/*; do
                    ln -sfn "$_n" "$asdk/ndk/$(basename "$_n")"; _realndk="$_n"
                  done
                  for _alias in 28.2.13676358; do
                    if [ ! -e "$asdk/ndk/$_alias" ] && [ -n "$_realndk" ]; then
                      mkdir -p "$asdk/ndk/$_alias"
                      for _f in "$_realndk"/*; do ln -sfn "$_f" "$asdk/ndk/$_alias/$(basename "$_f")"; done
                      rm -f "$asdk/ndk/$_alias/source.properties"
                      printf 'Pkg.Desc = Android NDK\nPkg.Revision = %s\n' "$_alias" > "$asdk/ndk/$_alias/source.properties"
                    fi
                  done
                fi
                # Same trick for the SDK CMake: a reown native plugin's
                # externalNativeBuild uses AGP's default cmake;3.22.1, which
                # nixpkgs doesn't ship. Expose the shipped CMake (4.1.2, patched)
                # under that alias. Safe: the plugins' cmake_minimum_required is
                # 3.10/3.14 (>= 3.5), which CMake 4.x still accepts.
                if [ -d "$_nix_sdk/cmake" ]; then
                  rm -f "$asdk/cmake"; mkdir -p "$asdk/cmake"
                  _realcmake=""
                  for _c in "$_nix_sdk"/cmake/*; do
                    ln -sfn "$_c" "$asdk/cmake/$(basename "$_c")"; _realcmake="$_c"
                  done
                  for _calias in 3.22.1; do
                    if [ ! -e "$asdk/cmake/$_calias" ] && [ -n "$_realcmake" ]; then
                      mkdir -p "$asdk/cmake/$_calias"
                      for _f in "$_realcmake"/*; do ln -sfn "$_f" "$asdk/cmake/$_calias/$(basename "$_f")"; done
                      rm -f "$asdk/cmake/$_calias/source.properties"
                      printf 'Pkg.Desc = Android SDK CMake\nPkg.Revision = %s\n' "$_calias" > "$asdk/cmake/$_calias/source.properties"
                    fi
                  done
                fi
                ln -sfn "$_nix_sdk" "$asdk/.nix-src"
              fi
              export ANDROID_HOME="$asdk"
              export ANDROID_SDK_ROOT="$asdk"
              # Emulator + AVD state must live in a writable home, never the SDK.
              export ANDROID_USER_HOME="''${ANDROID_USER_HOME:-$HOME/.android}"
              export ANDROID_AVD_HOME="''${ANDROID_AVD_HOME:-$HOME/.android/avd}"
              mkdir -p "$ANDROID_AVD_HOME"

              # SDK tools on PATH: adb, emulator, avdmanager, sdkmanager.
              # Add the legacy tools/bin FIRST so the modern cmdline-tools win
              # (prepend order = reverse priority). The legacy tools/bin
              # avdmanager/sdkmanager crash on JDK17 (removed JAXB / javax.xml.bind);
              # cmdline-tools bundle their own deps and run fine.
              export PATH="$ANDROID_SDK_ROOT/platform-tools:$ANDROID_SDK_ROOT/emulator:$PATH"
              for _ct in "$ANDROID_SDK_ROOT"/tools/bin "$ANDROID_SDK_ROOT"/cmdline-tools/*/bin "$ANDROID_SDK_ROOT"/cmdline-tools/latest/bin; do
                [ -d "$_ct" ] && export PATH="$_ct:$PATH"
              done

              # NDK lives at a versioned path under the SDK; expose it for Gradle.
              export ANDROID_NDK_ROOT="$(ls -d "$ANDROID_SDK_ROOT"/ndk/* 2>/dev/null | head -n1)"
              export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"

              # Force Gradle to use the Nix-patched aapt2 instead of the
              # dynamically-linked one it downloads from Maven (won't run on NixOS).
              _aapt2="$(ls "$ANDROID_SDK_ROOT"/build-tools/*/aapt2 2>/dev/null | head -n1)"
              if [ -n "$_aapt2" ]; then
                export GRADLE_OPTS="-Dorg.gradle.project.android.aapt2FromMavenOverride=$_aapt2 ''${GRADLE_OPTS:-}"
              fi

              echo "🟦 Flutter devShell ready — Android SDK (overlay) at $ANDROID_SDK_ROOT"
              echo "   emulator e2e:  ./dev-stack.sh e2e   (chain+relayer → emulator → integration_test)"
              echo "   sanity check:  flutter doctor -v"
            '';
          });
        }
      );
    };
}
