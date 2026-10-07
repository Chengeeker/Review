plugins {
    id("com.android.application")
}

android {
    namespace = "com.review.weibopoc"
    compileSdk = 35
    useLibrary("android.test.mock")

    defaultConfig {
        applicationId = "com.review.weibopoc"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "0.1.0"
        ndk {
            abiFilters.add("arm64-v8a")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
