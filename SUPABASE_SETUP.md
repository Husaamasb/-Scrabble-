# Supabase setup for سكرابل العربية

The browser app uses Supabase for accounts, profiles, friends, presence, rooms, private racks, chat, match results, rankings, and tournaments. The project is provisioned and the current schema is deployed.

## Existing project

- Project ref: `rwcwuxraekgpaeujhxbg`
- Region: `ap-south-1` (Mumbai)
- Project URL: `https://rwcwuxraekgpaeujhxbg.supabase.co`
- Database: PostgreSQL 17
- Current schema source: `supabase/schema.sql`

The production browser configuration is in `.env.production`. It contains only the public Supabase URL and publishable key. Never put a `service_role` key or any other secret in GitHub or browser code.

## One-time Auth dashboard setup

In Supabase → **Authentication → URL Configuration**:

- Site URL: `https://husaamasb.github.io`
- Redirect URLs:
  - `https://husaamasb.github.io/-Scrabble-/**`
  - `http://localhost:5173/**`

In **Authentication → Email Templates**, ensure the confirmation template includes `{{ .Token }}` so the six-digit sign-up verification code is included. Configure SMTP/email delivery and test it before inviting real players.

### Current account flows

- Account creation: email + password, followed by a six-digit email confirmation code.
- Sign-in: email + password.
- Password recovery: secure email link, followed by new password and confirmation fields.
- Google and Apple: buttons are present, but each provider must be enabled and configured in **Authentication → Providers** with its own credentials and the callback URL shown by Supabase.

**Important:** a separate email OTP challenge on every password sign-in is not implemented yet. The current six-digit OTP verifies new account creation.

## Secure administration

The admin section checks the server-managed Auth `app_metadata.scrabble_admin` claim. It never trusts editable `user_metadata`.

To grant the owner account access, open **Authentication → Users**, select the intended account, and add this field under **app_metadata**:

```json
{"scrabble_admin": true}
```

Do not place it in `user_metadata`. Refresh the account session after the change. The admin link then appears in the signed-in account page. The admin panel can review reports, moderate player accounts, close waiting rooms, manage dictionary overrides, and update tournament schedule/prizes/spectator settings. Server-side checks and RLS enforce the same admin permission.

## AI-first Arabic and English dictionary

Authenticated games use the server dictionary:

1. A deliberate admin word override takes priority.
2. A fresh trusted AI verdict cache entry is reused.
3. If the AI cache has no current result, the server asks the OpenAI Responses API to judge the exact spelling.
4. Wiktionary is used only if the AI provider is not configured or the AI request fails.

Guest/offline local play uses exact Wiktionary entry checks. Provider failures never automatically approve a word. AI verdicts are cached separately from Wiktionary results, so an old Wiktionary cache entry cannot bypass the AI-first check.

Configure these as **Supabase Edge Function secrets** (not GitHub secrets and not browser environment variables):

- `OPENAI_API_KEY` — private server-side key.
- `OPENAI_DICTIONARY_MODEL` — optional; defaults to `gpt-4.1-mini`.

The secret must never be pasted into chat or committed to the repository. A successful deployment alone does not prove the key works: make a real authenticated move and confirm the `scrabble-move` / `scrabble-dictionary` Edge Function logs report an AI verdict. During the latest code review, no recent dictionary invocation was present in the function logs, so live provider use still needs an authenticated end-to-end check.

## Online game security and rules

- The 15×15 public board, scores, turn index, word log, and remaining-tile count live in the room's public game state.
- The tile bag is server-owned. Browser roles have no access to `room_tile_bag`.
- Each player's rack is stored in `room_player_private`; RLS lets a player read only their own private row. Direct browser writes are revoked.
- The start RPC deals the starting-draw tiles, compares the closest tile to A/alif, redraws only tied players, and then deals seven tiles to each player.
- Online word placement goes through the authenticated `scrabble-move` Edge Function. It checks membership, turn ownership, revision, rack ownership, line placement, gaps, board connection, and every word formed. The database transaction independently reconstructs the words and scoring before changing the board or rack.
- The server applies premium squares only to newly placed tiles, scores cross-words, awards the seven-tile bonus, refills the rack, and advances the turn.
- Passing and tile exchanges use dedicated server-authoritative RPCs. Exchanges require at least seven tiles to remain in the bag.
- Endgame settlement is server-side: remaining rack values are handled when the bag is empty and a player empties their rack, after the scoreless-pass limit, or when the host ends the match.
- Reconnect grace is 120 seconds. The active client heartbeats and the server handles stale players and turn/host changes.
- Completed online matches record private per-player results and apply XP (+20 win, +15 draw, −5 loss), update win/loss/draw totals, and feed the leaderboards.

Room members can read public match state, but private racks and the server-owned bag are not published in room state or spectator data.

## Tournaments

The tournament lobby supports 4/8/16-player registration, single-elimination brackets, byes, and live updates. Completed room match results automatically advance winners; tied matches are marked for replay. Admins can set schedule, XP/coin prizes, and spectator access before a tournament starts.

## Schema changes

`supabase/schema.sql` is the tracked source for the deployed database schema. When database code changes, review the exact SQL diff and apply the intended migration/SQL patch to the connected project, then verify it with a read-only query and the relevant tests. Do not blindly re-run the entire schema for ordinary frontend or Edge Function changes.

## Remaining release checks

- Test SMTP delivery and the six-digit sign-up confirmation with a real account.
- Configure and test Google/Apple providers if they will be offered.
- Test a real authenticated AI dictionary verdict through a move; the recent logs did not yet show a live invocation.
- Complete end-to-end testing with at least two real player accounts, including room creation, turns, reconnect, pass/exchange, match settlement, and tournament advancement.
- Activate the intended owner account using `app_metadata.scrabble_admin`.
- Finish real-device visual/accessibility checks. The Android workflow creates a debug APK for testing; the iOS workflow creates an unsigned Simulator app, not an installable iPhone IPA. Signed store releases require platform signing credentials and the relevant developer accounts.
- Complete remaining profile presentation details such as avatar selection and achievement/badge display before calling the app release-ready.

Never treat client-submitted racks, scores, dictionary results, or admin flags as authoritative.