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

function normalizeWord(word: string, language: "ar" | "en") {
  const normalized = word.normalize("NFC").trim();
  if (!normalized || normalized.length > 80) throw new Error("Invalid word length.");
  if (language === "ar" && !/^[\u0600-\u06FF]+$/u.test(normalized)) throw new Error("Arabic words must contain Arabic letters only.");
  if (language === "en" && !/^[A-Za-z]+$/.test(normalized)) throw new Error("English words must contain English letters only.");
  return normalized;
}

async function aiDictionaryVerdict(word: string, language: "ar" | "en", apiKey: string) {
  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      Authorization: "Bearer " + apiKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: Deno.env.get("OPENAI_DICTIONARY_MODEL") || "gpt-4.1-mini",
      store: false,
      max_output_tokens: 80,
      instructions: "You are a conservative bilingual Scrabble lexicon adjudicator. Decide whether the exact supplied string is a recognized standalone lexical word in the specified language. Accept established dictionary headwords and ordinary inflected forms. Reject proper names, abbreviations, phrases, typos, invented strings, and uncertain cases. Do not translate, transliterate, repair, or add diacritics. For Arabic, accept standard Arabic lexical forms only; do not accept isolated particles unless they are established dictionary entries. If unsure, valid must be false. Return only the requested JSON object.",
      input: JSON.stringify({
        language: language === "ar" ? "Arabic" : "English",
        exact_word: word,
        task: "Is this exact spelling an accepted standalone word for a word board game?",
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
  if (!response.ok) throw new Error("AI dictionary request failed: " + response.status);
  const payload = await response.json();
  const text = (payload?.output ?? [])
    .filter((item: any) => item?.type === "message")
    .flatMap((item: any) => item?.content ?? [])
    .find((item: any) => item?.type === "output_text")?.text;
  if (typeof text !== "string") throw new Error("AI dictionary returned no structured verdict.");
  const verdict = JSON.parse(text);
  if (typeof verdict?.valid !== "boolean") throw new Error("AI dictionary verdict was malformed.");
  return verdict.valid;
}

async function dictionaryEntry(admin: any, word: string, language: "ar" | "en") {
  const normalized = normalizeWord(word, language);
  const { data: override, error: overrideError } = await admin
    .from("scrabble_dictionary_overrides")
    .select("is_valid")
    .eq("language", language)
    .eq("word", normalized)
    .maybeSingle();
  if (overrideError) throw overrideError;
  if (override) return { valid: Boolean(override.is_valid), source: "admin" };

  const { data: cached, error: cacheError } = await admin
    .from("scrabble_dictionary_cache")
    .select("is_valid,checked_at")
    .eq("language", language)
    .eq("word", normalized)
    .maybeSingle();
  if (cacheError) throw cacheError;
  if (cached) {
    const age = Date.now() - new Date(cached.checked_at).getTime();
    const ttl = cached.is_valid ? 30 * 24 * 60 * 60 * 1000 : 60 * 60 * 1000;
    if (Number.isFinite(age) && age >= 0 && age < ttl) {
      return { valid: Boolean(cached.is_valid), source: "cache" };
    }
  }

  let valid = false;
  let source = "wiktionary";
  let aiChecked = false;
  let wiktionaryAvailable = false;
  const openAiKey = Deno.env.get("OPENAI_API_KEY");

  // AI is the primary judge when configured; Wiktionary is the fallback.
  if (openAiKey) {
    try {
      valid = await aiDictionaryVerdict(normalized, language, openAiKey);
      source = "ai";
      aiChecked = true;
    } catch (error) {
      console.error("AI dictionary provider failed; trying Wiktionary fallback:", error);
    }
  }

  if (!aiChecked) {
    const url = new URL("https://" + language + ".wiktionary.org/w/api.php");
    url.search = new URLSearchParams({
      action: "query",
      format: "json",
      formatversion: "2",
      titles: normalized,
    }).toString();

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
    } catch (error) {
      console.warn("Wiktionary lookup failed:", error);
    }
  }

  // Do not cache a negative result if neither provider was available.
  if (valid || wiktionaryAvailable || aiChecked) {
    const { error } = await admin.from("scrabble_dictionary_cache").upsert({
      language,
      word: normalized,
      is_valid: valid,
      checked_at: new Date().toISOString(),
    }, { onConflict: "language,word" });
    if (error) console.error("Dictionary cache write failed:", error);
  }

  return { valid, source, aiChecked };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const { data: ctx, error: contextError } = await createSupabaseContext(req, { auth: "user" });
    if (contextError || !ctx) {
      return json({ error: contextError?.message || "Sign in required." }, contextError?.status || 401);
    }
    const body = await req.json();
    const language = body?.language === "ar" ? "ar" : body?.language === "en" ? "en" : null;
    if (!language || typeof body?.word !== "string") return json({ error: "A word and language are required." }, 400);
    const result = await dictionaryEntry(ctx.supabaseAdmin, body.word, language);
    console.info("Scrabble dictionary verdict:", JSON.stringify({
      language,
      source: result.source,
      aiChecked: result.aiChecked,
      valid: result.valid,
    }));
    return json(result);
  } catch (error) {
    console.error("Dictionary validation failed:", error);
    return json({ error: error instanceof Error ? error.message : "Dictionary validation failed." }, 400);
  }
});
