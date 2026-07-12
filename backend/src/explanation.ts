// LLM explanation provider. Swappable by design — GPT-4o-mini today, but the
// callers only depend on `generateExplanation`. Version-pinned model + capped
// output. Returns null when no key is configured (the app falls back to its
// own rule-based deltaReason text).

import type { Env, ExplainRequest } from "./types";

const MODEL = "gpt-4o-mini-2024-07-18"; // pinned snapshot — no silent price/behaviour drift
const MAX_TOKENS = 80;

const SYSTEM_PROMPT =
  "You are Sage, a friendly nutrition guide. In ONE supportive sentence (max 26 words), " +
  "explain how well this product fits the user's goal: lead with the main factor for or " +
  "against it, and briefly acknowledge the trade-off if there is one. If the personalized " +
  "score moved versus the overall, say why. If a dietary-restriction conflict is listed, " +
  "lead with that. " +
  "The app shows the user low/moderate/high badges for each nutrient; when 'Displayed " +
  "nutrient levels' are listed, your wording MUST agree with them — never describe a " +
  "nutrient as high or low unless that list says so. " +
  "Use ONLY the facts provided — never invent numbers, nutrients, or medical claims. " +
  "Address the user as 'you'; do not restate the score numbers.";

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

// `factors` are short signed drivers from the app's ScoringEngine:
//   "+ ..." = raised the personalized score, "- ..." = held it back.
// We split them so the model can explain the trade-off ("higher because X, even though Y").
function buildPrompt(i: ExplainRequest): string {
  const delta = i.your - i.overall;
  const sign = delta >= 0 ? "+" : "";
  const factors = i.factors ?? [];

  const strip = (f: string) => f.replace(/^\s*[+\-•]\s*/, "").trim();
  const raised = factors.filter((f) => f.trim().startsWith("+")).map(strip);
  const heldBack = factors.filter((f) => f.trim().startsWith("-")).map(strip);
  const other = factors.filter((f) => !/^\s*[+\-]/.test(f)).map(strip);

  const lines = [
    `Product: ${i.productName ?? "this product"}`,
    `Goal: ${i.objective ?? "maintain"}`,
    `Personalized score is ${delta === 0 ? "the same as" : delta > 0 ? "higher than" : "lower than"} the overall score (${sign}${delta}).`,
  ];
  if (raised.length) lines.push(`Speaks for it: ${raised.join("; ")}`);
  if (heldBack.length) lines.push(`Speaks against it: ${heldBack.join("; ")}`);
  if (other.length) lines.push(`Other notes: ${other.join("; ")}`);
  if (i.nutrientLevels?.length) {
    lines.push(`Displayed nutrient levels (your wording must agree): ${i.nutrientLevels.join("; ")}`);
  }
  lines.push("Write the one-sentence explanation of how it fits the user's goal.");
  return lines.join("\n");
}
