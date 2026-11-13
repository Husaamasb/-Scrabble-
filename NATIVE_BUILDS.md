# Android and iOS builds

The web app remains the single source of truth. Capacitor wraps the same built web app for Android and iOS; it does not replace or redraw the approved app icon.

## Requirements

- Node.js 22+
- Android Studio and Android SDK for Android builds
- macOS with Xcode for iOS builds
- A configured Supabase project for accounts and online features

## Install and create native projects

Run from the repository root:

```sh
npm install
npx cap add android
npx cap add ios
npm run cap:sync
```

Run `npx cap add ios` only on macOS with Xcode installed. Native platform directories are generated locally by Capacitor and are not included in the browser-only GitHub Pages deployment.

## Android APK

```sh
npm run cap:sync
npm run android
```

In Android Studio, choose **Build → Build Bundle(s) / APK(s) → Build APK(s)** for a test APK. For release, use **Generate Signed Bundle / APK** and keep the signing key private. Test installation and app icon on a real Android device before distribution.

## iPhone / iPad

```sh
npm run cap:sync
npm run ios
```

In Xcode, choose a valid Apple development team and bundle identifier, then run on a real iPhone. For distribution, use **Product → Archive** and the Apple distribution workflow. An Android APK cannot be installed on iOS; iOS requires an iOS build (IPA through Apple's signing/distribution process) or the installable Safari web app.

## Approved icon

The original approved asset is `public/icon.svg`. Keep it unchanged. It is already referenced by `index.html` and `public/manifest.webmanifest`. Before store submission, create the required platform-specific icon sizes from that exact source file without changing its artwork, cropping, wording, or colors. Confirm the icon in Android Studio and Xcode previews.
