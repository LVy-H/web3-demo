plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zkvote.tessera"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Stable Tessera application id (matches the namespace above). Fixed on
        // purpose: changing it post-release orphans installs and update channels.
        applicationId = "com.zkvote.tessera"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Internal / CI artifacts are intentionally DEBUG-signed so
            // `flutter run --release` and the CI `tessera-apk` upload work with
            // no secret in the repo. A production (Play / public sideload) build
            // must swap in a real keystore wired from env / CI secrets here
            // (storeFile / storePassword / keyAlias / keyPassword) — never
            // commit the keystore. Belongs to the release-pipeline work.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
