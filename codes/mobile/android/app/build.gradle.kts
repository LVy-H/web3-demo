plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zkvote.mobile"
    compileSdk = flutter.compileSdkVersion
    // Pin build-tools to the version the Nix-managed SDK provides. AGP's
    // default for this compileSdk is 35.0.0, which isn't in the image and would
    // be auto-installed into the read-only /nix/store (and fail). 36.1.0 ships
    // with the dev image. (compileSdk=36 resolves to platforms/android-36, which
    // the flake's SDK overlay aliases to the shipped android-36.1.)
    buildToolsVersion = "36.1.0"
    // Flutter's gradle plugin configures an NDK/CMake build for the app even
    // with no app-level native code; without these pins it tries to auto-install
    // ndk;27.0.12077973 + cmake;3.22.1 into the read-only Nix SDK (and the
    // prebuilt binaries wouldn't run on NixOS anyway). Pin both to the patched
    // versions the dev image ships.
    ndkVersion = "29.0.14206865"
    externalNativeBuild { cmake { version = "4.1.2" } }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zkvote.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
