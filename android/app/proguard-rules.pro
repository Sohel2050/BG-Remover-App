-keep class ai.onnxruntime.** { *; }

# --- Unity LevelPlay (ironSource) mediation + all listed ad networks ---
# These are the standard keep rules each network's own integration guide
# publishes; kept broad (whole-package keeps) because ad SDKs use heavy
# reflection and obfuscating their internals reliably breaks ad loading.

# LevelPlay / ironSource core
-keep class com.ironsource.** { *; }
-keep class com.ironsource.adapters.** { *; }
-dontwarn com.ironsource.**

# Chartboost
-keep class com.chartboost.** { *; }
-dontwarn com.chartboost.**

# Meta Audience Network
-keep class com.facebook.ads.** { *; }
-dontwarn com.facebook.ads.**

# InMobi
-keep class com.inmobi.** { *; }
-dontwarn com.inmobi.**

# Mintegral
-keep class com.mbridge.msdk.** { *; }
-dontwarn com.mbridge.msdk.**

# MobileFuse
-keep class com.mobilefuse.sdk.** { *; }
-dontwarn com.mobilefuse.sdk.**

# Moloco
-keep class com.moloco.sdk.** { *; }
-dontwarn com.moloco.sdk.**

# Ogury
-keep class co.ogury.** { *; }
-dontwarn co.ogury.**

# PubMatic / OpenWrap
-keep class com.pubmatic.sdk.** { *; }
-dontwarn com.pubmatic.sdk.**

# Smaato
-keep class com.smaato.sdk.** { *; }
-dontwarn com.smaato.sdk.**

# Unity Ads
-keep class com.unity3d.ads.** { *; }
-keep class com.unity3d.services.** { *; }
-dontwarn com.unity3d.ads.**
-dontwarn com.unity3d.services.**

# Verve / HyBid
-keep class net.pubnative.** { *; }
-dontwarn net.pubnative.**

# Yandex Mobile Ads
-keep class com.yandex.mobile.ads.** { *; }
-dontwarn com.yandex.mobile.ads.**

# Vungle / Liftoff
-keep class com.vungle.** { *; }
-dontwarn com.vungle.**

# AppLovin
-keep class com.applovin.** { *; }
-dontwarn com.applovin.**

# Google Play Services (ad id / appset — used by the LevelPlay plugin)
-keep class com.google.android.gms.ads.identifier.** { *; }
-keep class com.google.android.gms.appset.** { *; }
