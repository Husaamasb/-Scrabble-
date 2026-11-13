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

## 4. Whenever the schema is updated in the repository, run the full current `supabase/schema.sql` again in SQL Editor. The added functions use `create or replace` and can be safely reapplied. This enables room readiness, host-controlled match start, and the private per-player room-state table. The private table uses Row Level Security so each player can read only their own row. Direct client insert/update access is revoked until trusted server-side turn validation is implemented; hidden racks must never be stored in `rooms.game_state`. Premium squares are fixed by the standard board and cannot be edited in rooms. The private-state table is a security foundation only; live online turns and rack synchronization are still being implemented.

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

The cloud lobby and chat are not yet the same thing as a synchronized Scrabble match. The schema contains a revision-checked turn RPC, but execution is disabled until it can validate the complete move server-side. The browser currently does not read or write private racks, and direct client writes to `room_player_private` are revoked. This is a security foundation only, not a playable online match: initial server-side tile distribution, private rack delivery, full board/rack/turn UI integration, reconnect recovery, authoritative move/scoring/word validation, and online match result/XP persistence still need implementation and end-to-end testing. Do not trust client-submitted scores as authoritative. Do not treat the project as a finished release yet.


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

Direct client `INSERT` and `UPDATE` on `room_player_private` are intentionally disabled. Re-enable writes only through a trusted server-side turn pipeline that validates rack ownership, tile draws, move legality, dictionary results, and scoring. Never accept client-submitted racks or scores as authoritative.
