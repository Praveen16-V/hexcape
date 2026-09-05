import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing, read from android/key.properties.
//
// That file holds a password, so it is gitignored and is not in this repository
// and never will be. Create it yourself, alongside the keystore it points at:
//
//     keytool -genkey -v -keystore <path>/hexcape.jks \
//       -keyalg RSA -keysize 2048 -validity 10000 -alias hexcape
//
//     # android/key.properties
//     storeFile=<absolute path to hexcape.jks>
//     storePassword=...
//     keyPassword=...
//     keyAlias=hexcape
//
// Until it exists the release build falls back to the debug keystore, exactly
// as the Flutter template did, so `flutter build apk --release` keeps working
// for local testing. What it will *not* do any more is fall back silently: a
// debug-signed build is rejected by Play, and finding that out at upload time
// is worse than being told here.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
} else {
    logger.warn(
        "hexcape: android/key.properties not found — release builds will be " +
            "signed with the DEBUG keystore and cannot be uploaded to Play."
    )
}

android {
    namespace = "com.hexcape.hexcape"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Permanent once the first build is uploaded: Play identifies the app
        // by this string for the rest of its life and it cannot be changed.
        applicationId = "com.hexcape.hexcape"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
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
            signingConfig = if (hasReleaseKeystore) {
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
