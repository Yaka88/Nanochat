plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.util.Properties

val envVersionCode = System.getenv("NANOCHAT_VERSION_CODE")?.toIntOrNull()
val autoVersionCode = (System.currentTimeMillis() / 1000L).toInt()
val keyPropsFile = rootProject.file("key.properties")
val keyProps = Properties()
if (keyPropsFile.exists()) {
    keyProps.load(keyPropsFile.inputStream())
}
val hasUnifiedSigning = keyPropsFile.exists() &&
    keyProps.getProperty("storeFile") != null &&
    keyProps.getProperty("storePassword") != null &&
    keyProps.getProperty("keyAlias") != null &&
    keyProps.getProperty("keyPassword") != null

android {
        signingConfigs {
            if (hasUnifiedSigning) {
                create("unified") {
                    storeFile = file(keyProps.getProperty("storeFile"))
                    storePassword = keyProps.getProperty("storePassword")
                    keyAlias = keyProps.getProperty("keyAlias")
                    keyPassword = keyProps.getProperty("keyPassword")
                }
            }
        }

    namespace = "cn.bluelaser.nanochat"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "cn.bluelaser.nanochat"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = 36
        // Keep versionCode increasing so Android can install over old builds.
        // You can pin it in CI with env NANOCHAT_VERSION_CODE.
        versionCode = envVersionCode ?: autoVersionCode
        versionName = "1.0.1"
    }

    buildTypes {
        debug {
            if (hasUnifiedSigning) {
                signingConfig = signingConfigs.getByName("unified")
            }
        }
        release {
            signingConfig = if (hasUnifiedSigning) {
                signingConfigs.getByName("unified")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
