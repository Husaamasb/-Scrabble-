# سكرابل العربية | Scrabble

A bilingual Arabic/English Scrabble web app built with React, Vite, and Capacitor.

**Browser version:** https://husaamasb.github.io/-Scrabble-/

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
- Interactive wooden chest with a hinged lid, one horizontally scrollable row of face-down wooden tiles that flip to reveal on tap, a remaining-tile counter, selection highlights, rack refill, undo, and tile exchange. The computer's rack stays hidden during bot turns.
- AI-first Arabic/English dictionary for authenticated cloud play: server-side admin overrides, trusted AI verdict cache, then OpenAI Responses API word review. Wiktionary is a fallback only if the AI provider is unavailable; guest/offline play uses exact Wiktionary checks. Provider failures never auto-approve words.
- Confirmed dictionary entries are cached locally for later offline checks.
- Accepted move scoring, rack refill, and round history in the visible game screen.
- Playable same-device multiplayer mode for 2–4 players, with starting-player draw, private turn handoff, scoring, pass/exchange flow, match history, winner display, and automatic local match recovery.
- Fixed 15×15 premium-square layout shared by Arabic and English boards; premium positions cannot be edited by the host or players.
- Session engine for 2–4 players, starting-player draw, pass/exchange flow, and endgame settlement.
- Local active-game autosave and JSON backup import/export.
- Installable web-app manifest, service-worker shell cache, and the approved original icon asset at `public/icon.svg`.
- Supabase integration: email/password sign-up and login, six-digit email verification for new accounts, password recovery, Google/Apple OAuth hooks, player profiles, friend requests, online presence, room creation/join-by-code, room chat, and direct messages when configured. Room hosts choose either classic Scrabble ending or ending as soon as the tile bag is empty; turn timers are disabled.
- Friend QR sharing and image-based QR scanning (on browsers with BarcodeDetector), with manual player-ID search as a fallback.
- Account-backed tournament lobby with 4/8/16-player registration, host-controlled starts, single-elimination rounds, automatic byes, and progression from completed room match results.
- Cloud room initialization deals language-specific tiles on the server, keeps each rack private, resolves the starting player with tie redraws, and supports server-validated word placement, dictionary checks, scoring, rack refill, pass, exchange, and endgame settlement.
- Capacitor Android/iOS support plus automated GitHub Actions builds for an Android debug APK and an unsigned iOS Simulator app.
- Automated tests for the board engine, tile bags, sessions, and dictionary adapter.

## Still required for a complete release

- Password sign-in now verifies the password in a non-persistent client, sends a six-digit email OTP, and creates the main session only after the code is verified. Email OTP must be enabled in Supabase Auth and this flow still needs real-account testing. SMTP delivery, Google/Apple OAuth, and password recovery also need real-account testing.
- Profile avatar selection and achievement badges are implemented; badges are currently calculated from profile totals rather than stored as permanent award records.
- Complete end-to-end tests with at least two real players, including room reconnects, pass/exchange, match settlement, and automatic tournament advancement.
- Verify a real authenticated AI dictionary request in the Supabase Edge Function logs; code and deployments are ready, but a live provider verdict has not yet been observed in the recent logs.
- The owner account must be granted `scrabble_admin` in server-managed App Metadata before the admin dashboard is accessible.
- Final device-specific icon packaging and visual QA on real devices. **The approved artwork in `public/icon.svg` must remain unchanged.**
- Live end-to-end verification requires real accounts; no real-user room, reconnect, or tournament test is claimed yet.
- Signed Android/iOS store releases require real-device testing and platform signing. The Android artifact is a debug APK; the iOS Simulator artifact is unsigned and is not an installable iPhone IPA.

Guest/offline dictionary checks use Wiktionary's public MediaWiki API and require an internet connection for words not already cached. Authenticated cloud play uses the AI-first server validator, with Wiktionary only as a fallback if the AI provider is unavailable. The validator judges exact words and does not generate or suggest words.

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

- The wooden letter chest is part of both local and online match screens. Its hinged lid opens and closes; the active player's seven tiles sit in one horizontally scrollable row, face-down until individually flipped by tapping. In bot matches, the computer's rack remains hidden. Online games never expose the server's hidden tile bag.


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

The server checks admin dictionary overrides first, then trusted AI verdict cache entries, then asks the OpenAI Responses API to judge the exact spelling. Wiktionary is used only if the AI provider is unavailable. Results are cached server-side. Without the key, the app safely falls back to Wiktionary. Configure the key at [Supabase Edge Function Secrets](https://supabase.com/dashboard/project/rwcwuxraekgpaeujhxbg/functions/secrets).


## Admin operations

- Admin authorization is checked server-side against Supabase Auth `app_metadata.scrabble_admin`; client-editable user metadata is never used for privileges.
- The admin dashboard can review player reports, close waiting rooms, edit dictionary overrides, and adjust tournament schedules, prizes, and spectator access before registration closes.
- Player accounts can be suspended for 24 hours, 7 days, or 30 days, and suspensions can be lifted. Admin accounts and the current admin cannot be suspended through this tool.
- Player email and ban status are loaded through the authenticated `scrabble-admin` Edge Function; they are not exposed in the public profiles table.
- To grant the first administrator, the project owner must set `{"scrabble_admin":true}` in that user's **App Metadata** in Supabase Authentication → Users. Do not put this flag in User Metadata.
- Supabase Auth bans block new sign-ins; an already-issued access token can remain valid until it expires, so this is not an instant session-revocation guarantee.

## Deployed Edge Functions

- `scrabble-move`: server-authoritative online move validation and scoring.
- `scrabble-dictionary`: authenticated dictionary validation for local matches.
- `scrabble-admin`: admin-only player listing and account moderation.
