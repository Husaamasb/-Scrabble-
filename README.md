# Scrabble

A bilingual Arabic/English Scrabble web app built with React and Vite.

## Run locally

```bash
npm install
npm run dev
```

## Verify and build

```bash
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
- Fixed 15×15 premium-square layout shared by Arabic and English boards; only tile letters and language labels differ. The host and players cannot edit multiplier positions.
- Session engine for 2–4 players, starting-player draw, pass/exchange flow, and endgame settlement.
- Local active-game autosave and JSON backup import/export.
- Installable web-app manifest and service-worker shell cache.
- Supabase integration foundation: email/password auth, email OTP verification, password recovery, Google/Apple OAuth hooks, player profiles, friend requests, online presence, room creation/join-by-code, room chat, and direct messages when configured.
- Automated tests for the board engine, tile bags, sessions, and dictionary adapter.

## Not yet a complete release

The app includes a separate playable local match screen for same-device multiplayer and bot matches. Networked multiplayer and account-backed features are not complete. The following work remains:

- Online matchmaking, networked rooms and host synchronization (the current room UI is a local prototype; premium-square positions are fixed and identical in Arabic and English rooms), invites, tournaments, and daily challenges.
- Final hinged wooden chest animation and the original user-provided logo asset.
- Cloud backend activation requires a Supabase project, running `supabase/schema.sql`, and setting the two public Vite variables described in `SUPABASE_SETUP.md`.
- Full synchronized Scrabble gameplay inside network rooms, reconnect handling, tournaments, push notifications, and cloud match history are not complete.
- Rankings, XP, coins, badges, store, rewards, notifications, and statistics.
- Native Android/iOS packaging and device testing.
- Full end-to-end testing, including Arabic dictionary coverage and real-device offline behavior.

Dictionary data is retrieved from Wiktionary's public MediaWiki API. New words require an internet connection; previously confirmed exact entries are cached on the device. This adapter checks dictionary entry existence and does not generate or suggest words.

The repository is still under active development and must not be treated as a finished release.


## Languages

The interface supports two separate language modes: Arabic uses natural Saudi
colloquial wording, while English uses natural English copy. Switching the
language updates the app interface direction (RTL for Arabic, LTR for English).
Arabic and English game sections use their own tile sets and dictionary checks.
