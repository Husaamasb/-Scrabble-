# Scrabble

A bilingual Arabic/English Scrabble web app built with React and Vite.

## Run locally

```sh
npm install
npm run dev
```

## Verify and build

```sh
npm test
npm run build
```

GitHub Actions runs automated tests and the production build on pushes to `main`.

## Implemented

- Responsive Arabic/English interface and 15×15 board.
- Scrabble premium-square scoring, cross-word scoring, blank-tile zero value, and 50-point seven-tile bonus.
- User-specified Arabic (110) and English (100) tile sets.
- Face-down wooden tile chest, rack draw, undo, and return-pending-tiles controls.
- Exact-entry Arabic and English Wiktionary lookup. A move is accepted only when every formed word has an entry; lookup/network failures fail closed.
- Confirmed dictionary entries are cached locally for later offline checks.
- Accepted move scoring, rack refill, and round history in the visible game screen.
- Playable same-device multiplayer mode for 2–4 players, with starting-player draw, private turn handoff, scoring, pass/exchange flow, match history, winner display, and automatic local match recovery.
- Fixed 15×15 premium-square layout shared by Arabic and English boards; premium positions cannot be edited by the host or players.
- Session engine for 2–4 players, starting-player draw, pass/exchange flow, and endgame settlement.
- Local active-game autosave and JSON backup import/export.
- Installable web-app manifest, service-worker shell cache, and the approved original icon asset at `public/icon.svg`.
- Supabase integration foundation: email/password auth, email OTP verification, password recovery, Google/Apple OAuth hooks, player profiles, friend requests, online presence, room creation/join-by-code, room chat, and direct messages when configured.
- Cloud room initialization deals language-specific tiles on the server, keeps each rack private, resolves the starting player with tie redraws, and supports server-validated pass and tile-exchange actions. The cloud board remains read-only until authoritative word validation, placement, scoring, and rack refill are implemented.
- Capacitor configuration and native build instructions for Android and iOS.
- Automated tests for the board engine, tile bags, sessions, and dictionary adapter.

## Still required for a complete release

- Complete authoritative online Scrabble gameplay: server-side move geometry, dictionary verification, scoring, rack refill, endgame settlement, reconnect recovery, and online results.
- Full account-backed social features, matchmaking, invites, tournaments, daily challenges, rankings, XP, coins, badges, store, rewards, push notifications, and statistics.
- Full hinged chest animation and final device-specific icon packaging. **The approved artwork in `public/icon.svg` must remain unchanged.**
- Cloud backend activation requires a Supabase project, running `supabase/schema.sql`, and setting the two public Vite variables described in `SUPABASE_SETUP.md`.
- Native Android/iOS projects must be generated and built using Android Studio/SDK or macOS/Xcode. No signed APK or IPA is included yet.
- Full end-to-end testing, including Arabic dictionary coverage and real-device offline behavior.

Dictionary data is retrieved from Wiktionary's public MediaWiki API. New words require an internet connection; previously confirmed exact entries are cached on the device. This adapter checks dictionary entry existence and does not generate or suggest words.

The repository is still under active development and must not be treated as a finished release.

## Languages

The interface supports two separate language modes: Arabic uses natural Saudi colloquial
wording, while English uses natural English copy. Arabic and English game sections use
their own tile sets and dictionary checks. The app UI direction is RTL for Arabic and LTR
for English.

## Native Android and iOS builds

See [NATIVE_BUILDS.md](NATIVE_BUILDS.md) for the Capacitor setup and platform build steps.
An Android APK is not installable on iPhone/iPad; iOS requires a signed iOS build.
