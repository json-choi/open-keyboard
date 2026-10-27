plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }

// The one place for the app's identity. namespace is also the Kotlin package under src/*/java;
// to rename it, change this value and move those package folders. applicationId alone can change freely.
val appId = "io.github.jsonchoi.openkeyboard"

android {
    namespace = appId
    compileSdk = 36
    defaultConfig {
        applicationId = appId
        minSdk = 26
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"
    }
    buildFeatures { buildConfig = true }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildTypes {
        // Debug builds use the SDK's debug keystore. Release signing is yours to add; see README.md.
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    testOptions { unitTests.isReturnDefaultValues = true }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
