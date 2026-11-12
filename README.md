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
- Session engine for 2–4 players, starting-player draw, pass/exchange flow, and endgame settlement.
- Local active-game autosave and JSON backup import/export.
- Installable web-app manifest and service-worker shell cache.
- Automated tests for the board engine, tile bags, sessions, and dictionary adapter.

## Not yet a complete release

The visible screen currently supports a local single-player practice flow; the full 2–4 player session engine is not yet integrated into the screen. The following work remains:

- Full multiplayer turn UI, computer opponents (five levels), same-device play, online matchmaking, rooms, invites, tournaments, and daily challenges.
- Final hinged wooden chest animation and the original user-provided logo asset.
- Account creation, email verification, password reset, profiles, friends, chat, privacy controls, and cloud synchronization.
- Rankings, XP, coins, badges, store, rewards, notifications, and statistics.
- Native Android/iOS packaging and device testing.
- Full end-to-end testing, including Arabic dictionary coverage and real-device offline behavior.

Dictionary data is retrieved from Wiktionary's public MediaWiki API. New words require an internet connection; previously confirmed exact entries are cached on the device. This adapter checks dictionary entry existence and does not generate or suggest words.

The repository is still under active development and must not be treated as a finished release.
