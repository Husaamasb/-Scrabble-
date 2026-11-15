import { createSupabaseContext } from "npm:@supabase/server@1.6.1";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeCandidates(value: unknown, language: "ar" | "en") {
  if (!Array.isArray(value)) return [];
  const pattern = language === "ar" ? /^[\u0600-\u06FF]{2,15}$/u : /^[A-Za-z]{2,15}$/;
  const unique = new Set<string>();
  for (const item of value) {
    if (typeof item !== "string") continue;
    const word = item.normalize("NFC").trim();
    if (pattern.test(word)) unique.add(word);
    if (unique.size >= 80) break;
  }
  return [...unique];
}

async function generateCandidates(language: "ar" | "en", rack: unknown[], board: unknown[], apiKey: string) {
  const rackLetters = rack.map((tile: any) => tile?.isBlank ? "*" : String(tile?.letter ?? "")).filter(Boolean);
  const boardLetters = board.flatMap((tile: any, index: number) => {
    if (!tile) return [];
    const letter = String(tile.blankAs ?? tile.letter ?? "");
    return letter ? [{ row: Math.floor(index / 15), col: index % 15, letter }] : [];
  });
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: { Authorization: "Bearer " + apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_BOT_MODEL") || Deno.env.get("OPENAI_DICTIONARY_MODEL") || "gpt-4.1-mini",
      store: false,
      max_output_tokens: 1200,
      instructions: "You generate candidate words for a Scrabble computer player. Return only recognized standalone dictionary words in the requested language. Every candidate must be formable using one or more letters from the player's rack plus any existing board letters; each candidate must consume at least one rack tile. The client will independently verify exact placement, connectivity, and dictionary validity, so do not invent spellings. Do not return proper names, abbreviations, phrases, transliterations, or explanations. For Arabic, use standard Arabic spelling and no diacritics. Return up to 80 varied candidates, prioritizing words likely to fit the supplied board.",
      input: JSON.stringify({
        language: language === "ar" ? "Arabic" : "English",
        rack_letters: rackLetters,
        existing_board_letters: boardLetters,
        task: "Suggest candidate Scrabble words for the current rack and board.",
      }),
      text: {
        format: {
          type: "json_schema",
          name: "scrabble_bot_candidates",
          strict: true,
          schema: {
            type: "object",
            properties: { words: { type: "array", items: { type: "string" }, maxItems: 80 } },
            required: ["words"],
            additionalProperties: false,
          },
        },
      },
    }),
  });
  if (!response.ok) throw new Error("AI bot request failed: " + response.status);
  const payload = await response.json();
  const output = (payload?.output ?? [])
    .filter((item: any) => item?.type === "message")
    .flatMap((item: any) => item?.content ?? [])
    .find((item: any) => item?.type === "output_text")?.text;
  if (typeof output !== "string") throw new Error("AI bot returned no structured candidates.");
  const parsed = JSON.parse(output);
  return normalizeCandidates(parsed?.words, language);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);
  try {
    const { data: ctx, error } = await createSupabaseContext(req, { auth: "user" });
    if (error || !ctx) return json({ error: error?.message || "Sign in required." }, error?.status || 401);
    const body = await req.json();
    const language = body?.language === "ar" ? "ar" : body?.language === "en" ? "en" : null;
    if (!language || !Array.isArray(body?.rack) || body.rack.length < 1 || body.rack.length > 7 || !Array.isArray(body?.board) || body.board.length !== 225) {
      return json({ error: "A language, rack of up to seven tiles, and 15 by 15 board are required." }, 400);
    }
    const apiKey = Deno.env.get("OPENAI_API_KEY");
    if (!apiKey) return json({ error: "AI bot is not configured." }, 503);
    const words = await generateCandidates(language, body.rack, body.board, apiKey);
    return json({ words, source: "ai" });
  } catch (error) {
    console.error("Scrabble AI bot failed:", error);
    return json({ error: error instanceof Error ? error.message : "AI bot failed." }, 500);
  }
});
