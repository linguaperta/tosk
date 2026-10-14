import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: app/android/key.properties (git-ignored; see docs/release.md).
// Without it, release builds fall back to the debug key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "io.github.timoverlaan.tosk"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications (daily reminder) needs core library desugaring.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "io.github.timoverlaan.tosk"
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

    // Compress native libraries inside the APK (smaller download for sideloaded
    // previews; Android extracts them at install time).
    packaging {
        jniLibs {
            useLegacyPackaging = true
            // The Onyx pen SDK ships its own copy of the C++ runtime.
            pickFirsts += "**/libc++_shared.so"
        }
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Keep rules for the Onyx SDK (reflection into the e-reader framework).
            proguardFiles("proguard-rules.pro")
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Onyx (Boox) SDK, used only on ONYX devices behind a Build.MANUFACTURER
    // check (OnyxBridge.kt): low-latency pen raw drawing (TouchHelper) and
    // full e-ink refreshes (EpdController). Repository: repo.boox.com.
    implementation("com.onyx.android.sdk:onyxsdk-pen:1.5.8") {
        // Pre-AndroidX permission helper (JCenter era) that drags in the old
        // support library, which clashes with AndroidX. The pen and EPD code
        // paths don't ask for permissions.
        exclude(group = "pub.devrel", module = "easypermissions")
        exclude(group = "com.android.support")
    }
    implementation("com.onyx.android.sdk:onyxsdk-device:1.3.6")
    // The SDK calls Onyx framework APIs that Android 9+ hides from apps.
    implementation("org.lsposed.hiddenapibypass:hiddenapibypass:6.1")
}
