import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.albonik.bgremover"
    compileSdk = maxOf(flutter.compileSdkVersion, 36)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.albonik.bgremover"
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            // R8 shrinking is off: it removed classes ad SDKs need and the
            // release build crashed at startup. Rules are kept for safety.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    // --- Required by the unity_levelplay_mediation Flutter plugin ---
    implementation("com.google.android.gms:play-services-appset:16.0.2")
    implementation("com.google.android.gms:play-services-ads-identifier:18.0.1")
    implementation("com.google.android.gms:play-services-basement:18.3.0")
    // --- Mediated ad networks ---
    // Chartboost
    implementation("com.unity3d.ads-mediation:chartboost-adapter:5.9.0")
    implementation("com.chartboost:chartboost-sdk:9.14.0")
    // Meta Audience Network
    implementation("com.unity3d.ads-mediation:facebook-adapter:5.4.0")
    implementation("com.facebook.android:audience-network-sdk:6.22.0")
    // InMobi
    implementation("com.unity3d.ads-mediation:inmobi-adapter:5.9.0")
    implementation("com.inmobi.monetization:inmobi-ads-kotlin:11.4.1")
    // Mintegral
    implementation("com.unity3d.ads-mediation:mintegral-adapter:5.19.0")
    implementation("com.mbridge.msdk.oversea:mbridge_android_sdk:17.1.81")
    // MobileFuse
    implementation("com.unity3d.ads-mediation:mobilefuse-adapter:5.4.0")
    implementation("com.mobilefuse.sdk:mobilefuse-sdk-core:1.12.0")
    // Moloco
    implementation("com.unity3d.ads-mediation:moloco-adapter:5.17.0")
    implementation("com.moloco.sdk:moloco-sdk:4.12.0")
    // Ogury
    implementation("com.unity3d.ads-mediation:ogury-adapter:5.5.0")
    implementation("co.ogury:ogury-sdk:6.3.1")
    // PubMatic
    implementation("com.unity3d.ads-mediation:pubmatic-adapter:5.9.0")
    implementation("com.pubmatic.sdk:openwrap:5.3.0")
    // Smaato
    implementation("com.unity3d.ads-mediation:smaato-adapter:5.6.0")
    implementation("com.smaato.android.sdk:smaato-sdk:23.2.2")
    // Unity Ads
    implementation("com.unity3d.ads-mediation:unityads-adapter:5.11.0")
    implementation("com.unity3d.ads:unity-ads:4.19.0")
    // Verve
    implementation("com.unity3d.ads-mediation:verve-adapter:5.8.0")
    implementation("net.pubnative:hybid.sdk:3.9.2")
    // Yandex
    implementation("com.unity3d.ads-mediation:yandex-adapter:5.14.0")
    implementation("com.yandex.android:mobileads:8.4.0")
    // Vungle (Liftoff Monetize)
    implementation("com.unity3d.ads-mediation:vungle-adapter:5.14.0")
    implementation("com.vungle:vungle-ads:7.7.8")
    // AppLovin
    implementation("com.unity3d.ads-mediation:applovin-adapter:5.9.0")
    implementation("com.applovin:applovin-sdk:13.6.4")
}
