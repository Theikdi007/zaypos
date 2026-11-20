import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: android/key.properties (gitignored; docs/mobile/release-signing.md). Holds the upload
// keystore path, alias and passwords; never commit it, never put the passwords anywhere else.
val keyProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) FileInputStream(f).use { load(it) }
}
val hasReleaseKey = keyProperties.getProperty("storeFile") != null
val buildsRelease = gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }
if (buildsRelease && !hasReleaseKey) {
    // Never fall back to the debug key: a shop that installed a debug-signed APK could not update
    // to the real one without uninstalling (and losing unsent sales).
    throw GradleException(
        "Release build needs android/key.properties (storeFile, storePassword, keyAlias, keyPassword). " +
            "See docs/mobile/release-signing.md."
    )
}

android {
    namespace = "app.zaypos"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Registered with Firebase / Google Cloud (OAuth Android clients): changing it breaks Google Sign-In.
        applicationId = "app.zaypos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                // "~/..." is allowed in key.properties; Gradle does not expand it itself.
                storeFile = file(keyProperties.getProperty("storeFile").replaceFirst(Regex("^~"), System.getProperty("user.home")))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // Without key.properties a release build already stopped above; debug builds still configure.
            signingConfig = signingConfigs.getByName(if (hasReleaseKey) "release" else "debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
