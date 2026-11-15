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
- Hybrid Arabic/English dictionary: authenticated games check server-side admin overrides and cache, exact Wiktionary entries, then a conservative OpenAI Responses API lexicon review for missing entries. Guest/offline games retain exact Wiktionary checks. Provider failures never auto-approve words.
- Confirmed dictionary entries are cached locally for later offline checks.
- Accepted move scoring, rack refill, and round history in the visible game screen.
- Playable same-device multiplayer mode for 2–4 players, with starting-player draw, private turn handoff, scoring, pass/exchange flow, match history, winner display, and automatic local match recovery.
- Fixed 15×15 premium-square layout shared by Arabic and English boards; premium positions cannot be edited by the host or players.
- Session engine for 2–4 players, starting-player draw, pass/exchange flow, and endgame settlement.
- Local active-game autosave and JSON backup import/export.
- Installable web-app manifest, service-worker shell cache, and the approved original icon asset at `public/icon.svg`.
- Supabase integration: email/password auth, email OTP verification, password recovery, Google/Apple OAuth hooks, player profiles, friend requests, online presence, room creation/join-by-code, room chat, and direct messages when configured.
- Friend QR sharing and image-based QR scanning (on browsers with BarcodeDetector), with manual player-ID search as a fallback.
- Account-backed tournament lobby with 4/8/16-player registration, host-controlled starts, single-elimination rounds, automatic byes, and bracket progression; tournament hosts currently record match winners manually.
- Cloud room initialization deals language-specific tiles on the server, keeps each rack private, resolves the starting player with tie redraws, and supports server-validated word placement, dictionary checks, scoring, rack refill, pass, exchange, and endgame settlement.
- Capacitor Android/iOS support plus an automated macOS GitHub Actions build for the iOS Simulator.
- Automated tests for the board engine, tile bags, sessions, and dictionary adapter.

## Still required for a complete release

- Match tournament brackets to live room results automatically (current tournament hosts record bracket winners manually); add tournament scheduling, prizes, and spectator mode.
- Full account-backed social features, matchmaking, invites, tournaments, daily challenges, rankings, XP, coins, badges, store, rewards, push notifications, and statistics.
- Full hinged chest animation and final device-specific icon packaging. **The approved artwork in `public/icon.svg` must remain unchanged.**
- Supabase project provisioned and connected to the GitHub Pages production build through the public values in `.env.production`; database schema and migrations are installed. Authentication redirect URLs and the six-digit email template still need one-time dashboard configuration (see `SUPABASE_SETUP.md`).
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

See [NATIVE_BUILDS.md](NATIVE_BUILDS.md) for the Capacitor setup and platform build steps. The `Build Scrabble for iOS Simulator` workflow automatically builds an unsigned simulator app on macOS and uploads it as a 14-day artifact; it is not an App Store IPA.
An Android APK is not installable on iPhone/iPad; iOS requires a signed iOS build.


## Online Scrabble progress

Online rooms support server-validated word placement through the `scrabble-move` Edge Function and an atomic database function, exact dictionary-entry checks for the room language, server-side scoring and rack refill, a live score display and word log, and automatic endgame rack settlement. Realtime reconnect recovery restores an active room within the 120-second grace window. Completed online matches persist results and XP (+20 win, +15 draw, -5 loss), profile history, and global/weekly/monthly/Arabic/English leaderboards. The SQL source now includes the deployed word-placement RPC and its service-role-only dictionary cache. This is still an in-progress project, not a complete release.


## Tests

Run `npm test` to execute the automated board, move-validation, scoring, and tile-distribution tests before building the app.


## Player progression

Completed online matches are settled server-side. Final scores determine wins, draws, and losses; XP changes by +20 for a win, +15 for a draw, and -5 for a loss (XP never falls below zero). The profile shows progression totals and the player's own recent match history. Match-result rows are protected by RLS, and clients cannot directly change XP or match counters.


The online section includes global, weekly, monthly, Arabic-game, and English-game XP leaderboards. Period rankings use privacy-filtered aggregate records; raw match history remains private.


### Daily challenges
- Daily challenge progress is generated from verified match-result records on the server (play a match, win a match, score at least 100 points in a match).
- Rewards are claimed once per user per UTC day through an authenticated database function; clients cannot set their own progress or reward amounts.


## Daily challenges, notifications, and store

- Daily challenge progress is derived from server-recorded match results. Completed rewards are claimed through an authenticated database function.
- In-app notifications are private to each account and delivered in realtime for friend requests, room invitations, direct messages, turn starts, finished matches, and claimed daily rewards.
- The cosmetic store uses a server-controlled catalog, a virtual coin wallet, and a private inventory. Purchases are checked and charged in one database transaction; no real-money payments are enabled.
- Players can gift owned cosmetics to friends. Gift transfers are validated on the server, recipients can accept or reject, rejected items return to the sender, and gift notifications are generated automatically.
- The Supabase schema includes row-level security for notification, wallet, inventory, and catalog data. The store purchase RPC checks the authenticated user and cannot be called by anonymous users.


## Gameplay interface

- The wooden letter chest is part of both local and online match screens. Its hinged lid opens and closes, with the player's tiles shown in one organized row.
- In local games, the next seven shuffled bag tiles can be revealed one at a time; revealing another tile turns the previous one face down. Online games never expose the server's hidden tile bag.


## Account preferences and branding

- Signed-in players can save app language, light/dark appearance, sound, and notification preferences to their private account settings.
- The original user-provided Scrabble Arabic logo is restored in the app header and retained as the app icon artwork. It is used as supplied, not redrawn.


## Room moderation

- In public and friends-only rooms, the host can remove another player. The host cannot remove themselves through this control.
- With at least three active players, any active non-host player can propose removing another non-host player. The proposer casts the first yes vote automatically; the target cannot vote.
- Each eligible player gets one ballot. Removal requires a strict majority of eligible players; otherwise the proposal closes without removing anyone.
- Removal is processed by server-side functions, skips a removed player's turn when necessary, and is recorded in the room match log. A removed player is returned to the room list.


## AI dictionary configuration

The server-side AI dictionary uses an OpenAI API key stored only as a Supabase Edge Function secret. In the Supabase Dashboard for this project, open **Edge Functions → Secrets** and add:

- `OPENAI_API_KEY`: the private API key (never put it in the browser or GitHub).
- `OPENAI_DICTIONARY_MODEL` (optional): defaults to `gpt-4.1-mini`.

The AI review runs only when the exact Wiktionary lookup has no entry. Results are cached server-side; admin dictionary overrides take priority. Without the key, the app safely continues using Wiktionary. Configure the key at [Supabase Edge Function Secrets](https://supabase.com/dashboard/project/rwcwuxraekgpaeujhxbg/functions/secrets).
