import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.review"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    val keystorePropertiesFile = rootProject.file("key.properties")
    val keystoreProperties = Properties()
    if (keystorePropertiesFile.exists()) {
        keystoreProperties.load(FileInputStream(keystorePropertiesFile))
    }

    val customStoreFile = keystoreProperties.getProperty("storeFile")?.let { file(it) } ?: file("infinitycm.jks")
    val hasReleaseKey = customStoreFile.exists()

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = customStoreFile
                storePassword = keystoreProperties.getProperty("storePassword") ?: "infinitycm"
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: "infinitycm"
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: "infinitycm"
            }
        }
    }

    defaultConfig {
        applicationId = "com.review"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = 7
        versionName = "1.6"
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }

    packaging {
        jniLibs {
            excludes.add("lib/armeabi-v7a/**")
            excludes.add("lib/x86/**")
            excludes.add("lib/x86_64/**")
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
