# Scrabble

A bilingual Arabic/English Scrabble project built with React and Vite.

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

GitHub Actions runs the automated tests and production build on every push to `main`.

## Implemented and checked

- Responsive React/Vite application shell with Arabic and English interface switching.
- 15×15 board presentation and wooden visual styling.
- Deterministic move-placement validation: bounds, occupied cells, straight-line placement, gaps, center opening, and connection to existing tiles.
- Premium-square scoring engine: letter and word multipliers apply only to newly placed tiles; blank tiles can score zero; seven-tile bonus is included.
- English tile distribution: 100 tiles, matching the supplied table.
- Arabic tile distribution: 110 tiles, matching the supplied table, including separate hamza forms.
- Tile draw/exchange helpers and endgame leftover-tile settlement.
- Match-session state transitions for 2–4 players, dictionary-gated turn commits, pass/exchange flow, and starting-player draw comparison.
- Versioned local save/load/delete plus JSON backup import/export utilities.
- Installable web-app manifest and offline app-shell service worker.
- Automated tests for the game engine, tile distributions, endgame scoring, and PWA shell.

## Still required before this can be called a complete game

- A connected Arabic/English dictionary validation service. The adapter intentionally fails closed when no trusted validator is configured; it does not invent word validity.
- Integrating the engine and weighted tile bags into the visible game screen.
- Complete turn flow, player racks, bag counter, undo, pass, exchange UI, and full match state.
- Account creation, email verification, password reset, profiles, friends, messaging, online rooms, tournaments, rankings, rewards, and cloud synchronization.
- The original user-provided logo asset.
- Native Android/iOS packaging and device testing.

The current repository is a tested development foundation, not a finished release.
