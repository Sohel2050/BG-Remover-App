# Release build signing (so `flutter build appbundle --release` is
# actually signed for the Play Store, not debug-signed)

Right now `build.gradle.kts` has:
```kotlin
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")
    }
}
```
That's fine for `flutter run --release` to test locally, but the **Play
Store will reject a debug-signed bundle**. Here's the proper setup.

## 1. Generate an upload keystore (once, keep it forever)
```bash
keytool -genkey -v -keystore upload-keystore.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```
Run this from your project's `android/` folder (or anywhere — just note
the path). It'll ask for a password (remember it) and some identity
questions (name/org — can be anything, not user-facing).

**⚠️ Back this file up somewhere safe (password manager, encrypted
drive).** If you lose it, you can never update your app on the Play
Store again under the same listing — you'd have to publish as a new app.

## 2. Create `android/key.properties`
Copy `android/key.properties.example` (in this zip) to
`android/key.properties` and fill in your real values:
```properties
storePassword=<your keystore password>
keyPassword=<your key password — same as storePassword if you didn't set a separate one>
keyAlias=upload
storeFile=../upload-keystore.jks
```
`storeFile` is relative to the `android/app/` folder, so `../` points
back to `android/` where you generated the keystore (adjust the path if
you put it somewhere else, e.g. `/Users/sohel/keys/upload-keystore.jks`
for an absolute path).

**Add both to `.gitignore`** (create the file if it doesn't exist):
```
android/key.properties
android/upload-keystore.jks
*.jks
```

## 3. Update `android/app/build.gradle.kts`
Add this near the top, **before** the `android { ... }` block:
```kotlin
import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
```

Then inside the `android { ... }` block, add a `signingConfigs` block and
point `release` at it instead of `debug`:
```kotlin
android {
    // ... namespace, compileSdk, defaultConfig, etc. (unchanged) ...

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
            signingConfig = signingConfigs.getByName("release")
        }
    }
}
```

This way: if `key.properties` doesn't exist (e.g. a fresh clone without
your keystore), the release config just falls back to unsigned rather
than crashing the build — but on your machine, with the file in place,
release builds will be properly signed.

## 4. Build the release bundle for the Play Store
```bash
flutter build appbundle --release
```
Output: `build/app/outputs/bundle/release/app-release.aab` — this is
what you upload to Play Console.

## First submission vs. updates
- **First-ever submission**: Play Console can optionally re-sign your
  app with Google-managed "Play App Signing" — recommended, it also
  protects you if you ever lose your upload key (Google keeps the real
  signing key; your upload key can be reset via Play Console).
- **Updates**: you keep using the same `key.properties` / keystore for
  every future `flutter build appbundle` — the upload key must stay
  consistent across versions.
