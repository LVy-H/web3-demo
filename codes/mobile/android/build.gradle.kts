allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// On NixOS only the Nix-patched build-tools (36.1.0) actually run; Google's
// prebuilt binaries (d8/zipalign/apksigner) are dynamically linked and won't
// exec. Flutter plugin modules (e.g. integration_test) otherwise fall back to
// AGP's default build-tools 35.0.0 and try to auto-install it into the
// read-only Nix SDK, which fails. Force every Android module to the version the
// dev image ships. withPlugin fires as the AGP plugin applies (before the
// project is evaluated), so this is safe even though :app is evaluated eagerly.
subprojects {
    val proj = this
    val pin = {
        (proj.extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.buildToolsVersion = "36.1.0"
    }
    pluginManager.withPlugin("com.android.application") { pin() }
    pluginManager.withPlugin("com.android.library") { pin() }
}

// :jni (a reown transitive native plugin) sets `ndkVersion flutter.ndkVersion`,
// which resolves to an NDK nixpkgs doesn't ship (only 29.0.14206865 exists, and
// a Google-prebuilt NDK wouldn't run on NixOS anyway). :jni sets it during its
// own configuration — after the withPlugin hook above — so override it late,
// once every module is evaluated, onto the one NDK the Nix store provides.
gradle.projectsEvaluated {
    subprojects {
        (extensions.findByName("android") as? com.android.build.gradle.BaseExtension)
            ?.ndkVersion = "29.0.14206865"
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
