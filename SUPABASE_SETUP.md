# Supabase setup for Scrabble

The repository now contains the browser client and database schema for accounts, profiles, friends, presence, rooms, and chat. The app does not connect to a shared database until you create a Supabase project and configure the public project URL and anon/publishable key.

## 1. Create the backend

1. Open https://supabase.com/dashboard and create a new project.
2. Open **SQL Editor** in the project.
3. Open `supabase/schema.sql` in this repository, copy its full contents, paste it into SQL Editor, and run it.
4. In **Authentication → URL Configuration**, set the Site URL to `https://husaamasb.github.io`.
5. Add these Redirect URLs:
   - `https://husaamasb.github.io/-Scrabble-/**`
   - `http://localhost:5173/**`

## 2. Configure email verification

The app uses Supabase email/password sign-up and a six-digit email verification code. In **Authentication → Email Templates**, make sure the confirmation email includes the token variable `{{ .Token }}`. Email delivery must be configured and tested in Supabase before real users can receive verification codes.

Password recovery uses Supabase's secure recovery email link.

## 3. Configure social login (optional)

In **Authentication → Providers**, enable Google and/or Apple and enter the credentials from those providers. Set the provider callback URL to the callback URL shown by your Supabase project. The buttons remain unavailable until the provider is configured.

## 4. Whenever the schema is updated in the repository, run the full current `supabase/schema.sql` again in SQL Editor. The added functions use `create or replace` and can be safely reapplied. This enables room readiness, host-controlled match start, and the private per-player room-state table. The private table uses Row Level Security so each player can read only their own row. Direct client insert/update access is revoked; trusted RPCs alone initialize and modify private racks. Hidden racks must never be stored in `rooms.game_state`. Premium squares are fixed by the standard board and cannot be edited in rooms. The private-state table is protected from browser writes. Server-side pass and exchange actions are implemented; word placement and synchronized scoring are still being built.

5. Add the public project settings to GitHub Pages

In the GitHub repository, open **Settings → Secrets and variables → Actions → Variables** and create:

- `VITE_SUPABASE_URL`: the Project URL from Supabase → Project Settings → API.
- `VITE_SUPABASE_ANON_KEY`: the anon/publishable key from the same page.

These are public browser-client values protected by Supabase Row Level Security. **Never add a Supabase service_role key to this repository or browser app.**

A push to `main` will rebuild and deploy GitHub Pages using these variables. If they are empty, the app intentionally shows a setup message instead of pretending cloud features are connected.

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

The cloud lobby and chat are not yet a synchronized Scrabble match. Server-side tile distribution and private rack delivery are implemented, and the host start RPC now compares starting tiles, redraws tied players, and selects the first player using the closest tile to A/alif. The browser can read only the signed-in player's private rack and listens for realtime changes to that private row. Direct client writes to `room_player_private` remain revoked. The shared board is still display-only: authoritative move placement, dictionary validation, scoring, rack refill after a word, reconnect recovery, automatic endgame settlement, online result/XP persistence, and full end-to-end testing still need implementation. Passing and exchanging tiles now use dedicated server-side RPCs. Do not trust client-submitted scores as authoritative or treat the project as a finished release.


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

Players can exchange 1–7 selected tiles during their turn through
`exchange_scrabble_tiles`. The RPC locks the room and the caller's private
rack, verifies the revision, turn owner, membership, withdrawal status, and
that every unique selected tile belongs to that rack. It draws the same number
of replacements from the server-owned bag, returns the selected tiles to that
bag, updates only the caller's private rack, advances the turn, and records a
public exchange count without exposing tile identities. The browser has no
direct write permission to either private table. Re-run the complete
`supabase/schema.sql` in Supabase SQL Editor to install this RPC.
