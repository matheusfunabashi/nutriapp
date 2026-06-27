// LLM explanation provider. Swappable by design — GPT-4o-mini today, but the
// callers only depend on `generateExplanation`. Version-pinned model + capped
// output. Returns null when no key is configured (the app falls back to its
// own rule-based deltaReason text).

import type { Env, ExplainRequest } from "./types";

const MODEL = "gpt-4o-mini-2024-07-18"; // pinned snapshot — no silent price/behaviour drift
const MAX_TOKENS = 60;

const SYSTEM_PROMPT =
  "You explain a personalized food score in ONE short sentence (max 18 words). " +
  "Use ONLY the facts provided — never invent nutrition claims or numbers. " +
  "Speak directly to the user about why their score differs from the overall score.";

export async function generateExplanation(env: Env, input: ExplainRequest): Promise<string | null> {
  const apiKey = env.OPENAI_API_KEY;
  if (!apiKey) return null;

  const res = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: MAX_TOKENS,
      temperature: 0.4,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: buildPrompt(input) },
      ],
    }),
  });

  if (!res.ok) return null;
  const data = (await res.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  return data.choices?.[0]?.message?.content?.trim() ?? null;
}

function buildPrompt(i: ExplainRequest): string {
  const delta = i.your - i.overall;
  const sign = delta >= 0 ? "+" : "";
  const factors = (i.factors ?? []).join("; ") || "(none provided)";
  return [
    `Product: ${i.productName ?? "this product"}`,
    `Overall score: ${i.overall}/100`,
    `Personalized score: ${i.your}/100 (goal: ${i.objective ?? "maintain"}, difference: ${sign}${delta})`,
    `Drivers of the difference: ${factors}`,
    "Write one sentence explaining the personalized score.",
  ].join("\n");
}
