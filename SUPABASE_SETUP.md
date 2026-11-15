# Supabase setup for Scrabble

The repository contains the browser client and database schema for accounts, profiles, friends, presence, rooms, and chat. The Scrabble Supabase project is provisioned, the schema is installed, and the GitHub Pages workflow now reads the public configuration from `.env.production`.

## 1. Existing backend project

The Scrabble Supabase project has already been created and its database schema has been installed.

- Project ref: `rwcwuxraekgpaeujhxbg`
- Region: `ap-south-1` (Mumbai)
- Project URL: `https://rwcwuxraekgpaeujhxbg.supabase.co`
- Database: PostgreSQL 17
- The complete schema is tracked in `supabase/schema.sql` and installed as migrations.

The public browser configuration is stored in `.env.production`. It contains only the Supabase project URL and publishable key. Never add a `service_role` or secret key to the repository or browser app.

### One-time dashboard configuration still required

In Supabase → **Authentication → URL Configuration**:

- Set Site URL to `https://husaamasb.github.io`.
- Add Redirect URLs:
  - `https://husaamasb.github.io/-Scrabble-/**`
  - `http://localhost:5173/**`

In **Authentication → Email Templates**, make sure the confirmation email includes `{{ .Token }}` so the six-digit email verification code works. Configure and test email delivery before inviting real users.

## 2. Configure email verification

The app uses Supabase email/password sign-up and a six-digit email verification code. In **Authentication → Email Templates**, make sure the confirmation email includes the token variable `{{ .Token }}`. Email delivery must be configured and tested in Supabase before real users can receive verification codes.

Password recovery uses Supabase's secure recovery email link.

## 3. Configure social login (optional)

In **Authentication → Providers**, enable Google and/or Apple and enter the credentials from those providers. Set the provider callback URL to the callback URL shown by your Supabase project. The buttons remain unavailable until the provider is configured.

## 4. Whenever the schema is updated in the repository, run the full current `supabase/schema.sql` again in SQL Editor. The added functions use `create or replace` and can be safely reapplied. This enables room readiness, host-controlled match start, and the private per-player room-state table. The private table uses Row Level Security so each player can read only their own row. Direct client insert/update access is revoked; trusted RPCs alone initialize and modify private racks. Hidden racks must never be stored in `rooms.game_state`. Premium squares are fixed by the standard board and cannot be edited in rooms. The private-state table is protected from browser writes. Server-side pass and exchange actions are implemented; word placement and synchronized scoring are still being built.

## 5. Production build configuration

The GitHub Pages workflow reads `.env.production` during `npm run build`. That file contains only the public project URL and publishable key. A push to `main` triggers the production build and Pages deployment. Never add a `service_role` or secret key to the repository or browser app.

## 6. Local development

Copy `.env.example` to `.env.local`, fill in the same two public values, then run:

```bash
npm install
npm run dev
```

## What works after setup

- Email/password account registration and sign-in.
- Six-digit email verification (requires the Supabase confirmation template to use `{{ .Token }}`).
- Password reset email.
- Optional Google and Apple OAuth when configured in Supabase.
- Player profile and privacy setting.
- Friend search by public player ID or username, requests, and accept/reject.
- Online presence while the cloud section is open.
- Public/private rooms, 2–4 player capacity, six-digit room code, joining, room chat, and direct friend messages.\n- Room member ready status and host-controlled start after at least two players join and everyone is ready.

## Still required for a complete online game

The cloud lobby and chat are not yet a synchronized Scrabble match. Server-side tile distribution and private rack delivery are implemented, and the host start RPC compares starting tiles, redraws tied players, and selects the first player using the closest tile to A/alif. The browser can read only the signed-in player's private rack and listens for realtime changes to that private row. The current dictionary check is an exact-entry lookup against Wiktionary, not an AI model; AI-based word adjudication is not enabled yet. Direct client writes to `room_player_private` remain revoked. Word placement now uses the `scrabble-move` Edge Function: it authenticates the player, validates the proposed line against the authoritative rack and board, checks every formed word against the language-specific Wiktionary entry API with a private server-side cache, and calls a service-role-only SQL transaction that independently rebuilds the words, checks the submitted dictionary result, calculates premium-square scores, refills the rack, updates the board, and advances the turn. The client cannot execute the privileged move RPC directly. Passing and exchanging tiles continue to use dedicated server-side RPCs. Endgame settlement now runs on the server after two full rounds of scoreless turns, when the bag is empty and a player empties their rack, or when the host ends the match; remaining rack values are deducted and awarded according to the finish condition. A server-enforced 120-second reconnect grace is now implemented: the active client refreshes a heartbeat every 20 seconds (and when the tab becomes visible), and a Supabase Cron job checks every 30 seconds. When a player's heartbeat is stale for more than 120 seconds, the server marks them withdrawn, skips their turn when needed, transfers host control if needed, and settles the match if one or zero active players remain. If the player reopens the app within the grace period, their active room is restored automatically and their seat is preserved. Full end-to-end multiplayer testing is still outstanding. Match completion now records private per-player results and updates XP (+20 win, +15 draw, -5 loss) and win/draw/loss counters server-side; players can view their own recent match history. The online page also shows a public XP leaderboard using profiles with Everyone privacy, sorted by XP and then wins. A manual withdrawal is recorded as a loss; if only one active player remains, the room is settled automatically, and a player withdrawing on their turn is skipped. The `scrabble_match_results` table has RLS enabled and authenticated users can read only their own rows; direct writes are denied. Profile progression columns are not updateable by clients, while username, bio, privacy, and avatar presentation fields remain editable. Do not trust client-submitted scores as authoritative or treat the project as a finished release.


## Ending an online room match

The room host can now end a match with the `finish_scrabble_room` RPC. It checks
the signed-in user against `rooms.host_id`, changes the room status to
`finished`, and records `finish_reason: "host"` in the public game state.
The shared score panel is shown only after the room is finished.

After updating the repository, run the complete `supabase/schema.sql` file
again in the Supabase SQL Editor so the new RPC is installed. Automatic
end-of-bag completion is not enabled yet: the server-side tile bag and rack
turn engine still need to be implemented and validated.


## Player withdrawal

The active-room screen includes a withdrawal button with a confirmation dialog.
Confirming calls `withdraw_scrabble_room`, which marks only that member as
withdrawn and does not finish the room for everyone else. The requested label
and confirmation wording are displayed exactly in Arabic.

Important: the displayed “30 ريال و15 XP” wording is not a live charge in this
version. No real-money payment or XP deduction is performed; the project has
no verified wallet/payment and XP ledger for this action. The dialog explicitly
discloses this. Run the complete `supabase/schema.sql` file in Supabase after
updating to install the withdrawal column and RPC.


## Private rack write protection

Direct client `INSERT` and `UPDATE` on `room_player_private` are intentionally disabled. The server-side start and exchange RPCs can update private racks without granting browser write access. Future move RPCs must validate rack ownership, tile draws, move legality, dictionary results, and scoring. Never accept client-submitted racks or scores as authoritative.


## Server-side cloud tile dealing (new)

The latest schema overrides `start_scrabble_room` to build a shuffled server-owned tile bag using the language-specific distribution. It deals one private starting-draw tile and seven rack tiles per player. The Arabic set matches the user's latest table and totals 110 tiles, including separate entries for `ئ أول الكلمة` (10 points, 2 tiles) and `ئ` (8 points, 1 tile), plus `ى` (3 points, 1 tile) and two jokers. The bag table has RLS enabled and no client privileges; each player can select only their own `room_player_private` row. The cloud screen displays only the signed-in player's rack and refreshes it from realtime row updates.

The server now resolves the starting draw during `start_scrabble_room`: it compares the closest tile to A/alif, redraws only tied players, and stores the public draw history and starter ID. This is still an initialization step, not a complete online game. Server-authoritative tile placement, word/dictionary validation, scoring, rack refill after a valid word, automatic endgame settlement, and full end-to-end multiplayer tests remain outstanding. Passing and exchanging tiles now have dedicated server-authoritative RPCs. Do not enable `submit_scrabble_turn` or client write access to private racks until those checks are implemented.


## Server-authoritative pass turn

The cloud match now supports passing a turn through `pass_scrabble_turn`. The RPC locks the room row, checks the active match, membership, withdrawal status, turn owner, and expected revision, then advances to the next non-withdrawn player and records the pass in the public log. It does not accept client-supplied board, score, rack, or bag data. The browser displays the pass button only for the current player. Run the complete `supabase/schema.sql` in Supabase SQL Editor to install this RPC.

Tile placement, dictionary validation, scoring, rack refill after a word, and endgame settlement remain disabled until their own authoritative server-side implementation and tests are complete. Tile exchanges are now implemented separately through `exchange_scrabble_tiles`.


## Server-authoritative tile exchange

Players can exchange 1–7 selected tiles during their turn, following the standard rule that at least seven tiles must remain in the bag, through
`exchange_scrabble_tiles`. The RPC locks the room and the caller's private
rack, verifies the revision, turn owner, membership, withdrawal status, and
that every unique selected tile belongs to that rack. It draws the same number
of replacements from the server-owned bag, returns the selected tiles to the bag and shuffles it, updates only the caller's
private rack, advances the turn, and records a
public exchange count without exposing tile identities. The browser has no
direct write permission to either private table. Re-run the complete
`supabase/schema.sql` in Supabase SQL Editor to install this RPC.
