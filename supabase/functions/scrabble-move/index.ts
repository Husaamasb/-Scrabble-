import { createSupabaseContext } from "npm:@supabase/server@1.6.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const premium = (() => {
  const result = new Map<number, string>();
  const mirror = (pairs: number[][]) => pairs.flatMap(([r, c]) => [
    [r, c], [r, 14 - c], [14 - r, c], [14 - r, 14 - c],
  ]);
  const put = (cells: number[][], kind: string) => {
    for (const [r, c] of cells) result.set(r * 15 + c, kind);
  };
  put([[0,0],[0,7],[0,14],[7,0],[7,14],[14,0],[14,7],[14,14]], "TW");
  put(mirror([[1,3],[2,2],[3,1],[4,4]]).concat([[7,7]]), "DW");
  put(mirror([[1,5],[5,1],[5,5]]), "TL");
  put([[0,3],[0,11],[2,6],[2,8],[3,0],[3,7],[3,14],[6,2],[6,6],[6,8],[6,12],[7,3],[7,11],[8,2],[8,6],[8,8],[8,12],[11,0],[11,7],[11,14],[12,6],[12,8],[14,3],[14,11]], "DL");
  return result;
})();

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function tileAt(board: any[], proposed: Map<number, any>, index: number) {
  return proposed.get(index) ?? board[index] ?? null;
}

function evaluate(boardInput: any[], rack: any[], placements: any[]) {
  if (!Array.isArray(placements) || placements.length < 1 || placements.length > 7) {
    throw new Error("Place between 1 and 7 tiles.");
  }
  const board = boardInput.length === 0 ? Array(225).fill(null) : [...boardInput];
  if (board.length !== 225) throw new Error("The match board has an invalid size.");

  const proposed = new Map<number, any>();
  const usedIds = new Set<string>();
  const normalized: any[] = [];
  for (const item of placements) {
    const row = Number(item?.row), col = Number(item?.col);
    const tileId = String(item?.tileId ?? "");
    if (!Number.isInteger(row) || !Number.isInteger(col) || row < 0 || row > 14 || col < 0 || col > 14 || !tileId) {
      throw new Error("Invalid tile placement.");
    }
    const index = row * 15 + col;
    if (proposed.has(index) || board[index]) throw new Error("That square is already occupied.");
    if (usedIds.has(tileId)) throw new Error("A tile cannot be used twice.");
    const tile = rack.find((candidate) => candidate?.id === tileId);
    if (!tile) throw new Error("A selected tile is not in your rack.");
    let placed = { ...tile };
    if (tile.isBlank) {
      const blankAs = String(item.blankAs ?? "").trim();
      if (!blankAs || blankAs.length > 8) throw new Error("Choose the letter represented by the blank tile.");
      placed.blankAs = blankAs;
      placed.points = 0;
    } else {
      delete placed.blankAs;
    }
    proposed.set(index, placed);
    usedIds.add(tileId);
    normalized.push({ row, col, tileId, ...(tile.isBlank ? { blankAs: placed.blankAs } : {}) });
  }

  const rows = [...new Set(normalized.map((p) => p.row))];
  const cols = [...new Set(normalized.map((p) => p.col))];
  if (rows.length !== 1 && cols.length !== 1) throw new Error("Tiles must be placed in one straight line.");
  const horizontal = rows.length === 1;
  const axisValues = normalized.map((p) => horizontal ? p.col : p.row);
  const min = Math.min(...axisValues), max = Math.max(...axisValues);
  const fixed = horizontal ? rows[0] : cols[0];
  for (let n = min; n <= max; n++) {
    const index = horizontal ? fixed * 15 + n : n * 15 + fixed;
    if (!tileAt(board, proposed, index)) throw new Error("There cannot be a gap between placed tiles.");
  }

  const firstMove = board.every((tile) => !tile);
  if (firstMove) {
    if (!proposed.has(112)) throw new Error("The first word must cover the center square.");
  } else {
    const connected = [...proposed.keys()].some((index) => [
      index >= 15 ? index - 15 : -1,
      index < 210 ? index + 15 : -1,
      index % 15 > 0 ? index - 1 : -1,
      index % 15 < 14 ? index + 1 : -1,
    ].some((near) => near >= 0 && Boolean(board[near])));
    if (!connected) throw new Error("Your word must connect to an existing tile.");
  }

  const words = new Map<string, { word: string; cells: number[]; points: number }>();
  for (const index of proposed.keys()) {
    for (const [step, direction] of [[1, "horizontal"], [15, "vertical"]] as const) {
      let start = index;
      while (start - step >= 0 && (step !== 1 || Math.floor(start / 15) === Math.floor((start - step) / 15)) && tileAt(board, proposed, start - step)) {
        start -= step;
      }
      const cells: number[] = [];
      const letters: string[] = [];
      let subtotal = 0, wordMultiplier = 1;
      for (let cursor = start; cursor < 225; cursor += step) {
        if (step === 1 && Math.floor(cursor / 15) !== Math.floor(start / 15)) break;
        const tile = tileAt(board, proposed, cursor);
        if (!tile) break;
        cells.push(cursor);
        letters.push(String(tile.blankAs ?? tile.letter ?? ""));
        let points = Number(tile.points) || 0;
        if (proposed.has(cursor)) {
          const kind = premium.get(cursor);
          if (kind === "DL") points *= 2;
          if (kind === "TL") points *= 3;
          if (kind === "DW") wordMultiplier *= 2;
          if (kind === "TW") wordMultiplier *= 3;
        }
        subtotal += points;
      }
      if (cells.length > 1) {
        const key = direction + ":" + start;
        if (!words.has(key)) {
          words.set(key, { word: letters.join(""), cells, points: subtotal * wordMultiplier });
        }
      }
    }
  }
  if (!words.size) throw new Error("The move must create at least one word.");
  const wordList = [...words.values()];
  const total = wordList.reduce((sum, word) => sum + word.points, 0) + (placements.length === 7 ? 50 : 0);
  return { words: wordList, total, normalized };
}

async function dictionaryEntry(admin: any, word: string, language: "ar" | "en") {
  const normalized = word.trim();
  const { data: override } = await admin.from("scrabble_dictionary_overrides").select("is_valid").eq("language", language).eq("word", normalized).maybeSingle();
  if (override) return Boolean(override.is_valid);
  const { data: cached } = await admin
    .from("scrabble_dictionary_cache")
    .select("is_valid,checked_at")
    .eq("language", language)
    .eq("word", normalized)
    .maybeSingle();
  if (cached) {
    const age = Date.now() - new Date(cached.checked_at).getTime();
    const ttl = cached.is_valid ? 30 * 24 * 60 * 60 * 1000 : 60 * 60 * 1000;
    if (Number.isFinite(age) && age >= 0 && age < ttl) return Boolean(cached.is_valid);
  }

  const url = new URL("https://" + language + ".wiktionary.org/w/api.php");
  url.search = new URLSearchParams({
    action: "query",
    format: "json",
    formatversion: "2",
    titles: normalized,
  }).toString();
  let valid = false;
  let wiktionaryAvailable = false;
  try {
    const response = await fetch(url, {
      headers: { Accept: "application/json", "User-Agent": "ScrabbleArabic/0.3.0" },
      signal: AbortSignal.timeout(4500),
    });
    if (response.ok) {
      const data = await response.json();
      const page = data?.query?.pages?.[0];
      valid = Boolean(page && !page.missing && !page.invalid);
      wiktionaryAvailable = true;
    }
  } catch (lookupError) {
    console.warn("Wiktionary lookup failed:", lookupError);
  }

  let aiChecked = false;
  const openAiKey = Deno.env.get("OPENAI_API_KEY");
  if (!valid && openAiKey) {
    try {
      const aiResponse = await fetch("https://api.openai.com/v1/responses", {
        method: "POST",
        headers: {
          Authorization: "Bearer " + openAiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          model: Deno.env.get("OPENAI_DICTIONARY_MODEL") || "gpt-4.1-mini",
          store: false,
          max_output_tokens: 80,
          instructions: "You are a conservative bilingual Scrabble lexicon adjudicator. Decide whether the exact supplied string is a recognized standalone lexical word in the specified language. Accept established dictionary headwords and ordinary inflected forms. Reject proper names, abbreviations, phrases, typos, invented strings, and uncertain cases. Do not translate, transliterate, repair, or add diacritics. If unsure, valid must be false. Return only the requested JSON object.",
          input: JSON.stringify({
            language: language === "ar" ? "Arabic" : "English",
            exact_word: normalized,
          }),
          text: {
            format: {
              type: "json_schema",
              name: "scrabble_word_verdict",
              strict: true,
              schema: {
                type: "object",
                properties: { valid: { type: "boolean" } },
                required: ["valid"],
                additionalProperties: false,
              },
            },
          },
        }),
      });
      if (!aiResponse.ok) throw new Error("AI dictionary request failed: " + aiResponse.status);
      const aiData = await aiResponse.json();
      const content = (aiData?.output ?? [])
        .filter((item: any) => item?.type === "message")
        .flatMap((item: any) => item?.content ?? [])
        .find((item: any) => item?.type === "output_text")?.text;
      if (typeof content !== "string") throw new Error("AI dictionary returned no structured verdict.");
      const verdict = JSON.parse(content);
      if (typeof verdict?.valid !== "boolean") throw new Error("AI dictionary verdict was malformed.");
      valid = verdict.valid;
      aiChecked = true;
    } catch (aiError) {
      console.error("AI dictionary fallback failed:", aiError);
    }
  }

  // Never cache a negative result when both providers were unavailable.
  if (valid || wiktionaryAvailable || aiChecked) {
    await admin.from("scrabble_dictionary_cache").upsert({
    language,
    word: normalized,
    is_valid: valid,
    checked_at: new Date().toISOString(),
    }, { onConflict: "language,word" });
  }
  return valid;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const { data: ctx, error: contextError } = await createSupabaseContext(req, { auth: "user" });
    if (contextError || !ctx) {
      return json({ error: contextError?.message || "Sign in required." }, contextError?.status || 401);
    }
    const actor = ctx.userClaims?.sub;
    if (!actor) return json({ error: "Sign in required." }, 401);

    const body = await req.json();
    const roomId = String(body?.room_id ?? "");
    const expectedRevision = Number(body?.expected_revision);
    const placements = body?.placements;
    if (!roomId || !Number.isInteger(expectedRevision) || !Array.isArray(placements)) {
      return json({ error: "Invalid move request." }, 400);
    }

    const admin = ctx.supabaseAdmin;
    const [{ data: room, error: roomError }, { data: privateRow, error: privateError }, { data: member, error: memberError }] = await Promise.all([
      admin.from("rooms").select("id,language,status,game_state").eq("id", roomId).single(),
      admin.from("room_player_private").select("private_state").eq("room_id", roomId).eq("user_id", actor).single(),
      admin.from("room_members").select("user_id,is_withdrawn").eq("room_id", roomId).eq("user_id", actor).single(),
    ]);
    if (roomError || !room) return json({ error: "Room not found." }, 404);
    if (privateError || !privateRow) return json({ error: "Your private rack was not found." }, 409);
    if (memberError || !member || member.is_withdrawn) return json({ error: "Active room membership required." }, 403);
    if (room.status !== "playing") return json({ error: "Match is not active." }, 409);
    const state = room.game_state ?? {};
    if (Number(state.revision ?? 0) !== expectedRevision) return json({ error: "Game state changed; refresh and try again." }, 409);
    const playerIds = state.player_ids ?? [];
    const turnIndex = Number(state.turn_index ?? -1);
    if (!Array.isArray(playerIds) || playerIds[turnIndex] !== actor) return json({ error: "It is not your turn." }, 403);

    const rack = privateRow.private_state?.rack;
    if (!Array.isArray(rack)) return json({ error: "Your rack is invalid." }, 409);
    const result = evaluate(Array.isArray(state.board) ? state.board : [], rack, placements);
    const language = room.language === "ar" ? "ar" : room.language === "en" ? "en" : null;
    if (!language) return json({ error: "Unsupported room language." }, 400);

    const uniqueWords = [...new Set(result.words.map((word) => word.word))].sort();
    const checks = await Promise.all(uniqueWords.map(async (word) => ({ word, valid: await dictionaryEntry(admin, word, language) })));
    const invalid = checks.filter((check) => !check.valid);
    if (invalid.length) return json({ error: "Word not found in the " + (language === "ar" ? "Arabic" : "English") + " dictionary: " + invalid.map((x) => x.word).join(", ") }, 422);

    const { data: updatedRoom, error: moveError } = await admin.rpc("place_scrabble_word", {
      target_room: roomId,
      expected_revision: expectedRevision,
      placements: result.normalized,
      validated_words: uniqueWords,
      actor,
    });
    if (moveError) {
      const conflict = /revision|changed|turn|occupied|rack|connect|gap|center/i.test(moveError.message);
      return json({ error: moveError.message }, conflict ? 409 : 422);
    }
    return json({ room: updatedRoom, words: result.words, points: result.total });
  } catch (error) {
    console.error("scrabble-move:", error);
    return json({ error: error instanceof Error ? error.message : "Could not validate this move." }, 500);
  }
});
