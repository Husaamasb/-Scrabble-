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

## 4. Whenever the schema is updated in the repository, run the full current `supabase/schema.sql` again in SQL Editor. The added functions use `create or replace` and can be safely reapplied. This enables room readiness, host-controlled match start, and saving the host's 15×15 premium-square layout.\n\n5. Add the public project settings to GitHub Pages

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
- Public/private rooms, 2–4 player capacity, six-digit room code, joining, room chat, and direct friend messages.\n- Room member ready status and host-controlled start after at least two players join and everyone is ready.\n- Host editor for the 15×15 premium-square layout (TW/DW/TL/DL/start), saved to the room.

## Still required for a complete online game

The cloud lobby and chat are not yet the same thing as a synchronized Scrabble match. Live board/rack/turn synchronization after the lobby starts, reconnect recovery, authoritative server-side scoring/word validation, room invitations inbox, and online match result/XP persistence still need implementation and end-to-end testing. Do not treat the project as a finished release yet.
