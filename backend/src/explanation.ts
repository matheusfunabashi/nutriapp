// LLM overview provider with deterministic validation + template fallback.

import type { Env, ExplainRequest, OverviewContext } from "./types";

const MODEL = "gpt-4o-mini-2024-07-18";
const MAX_TOKENS = 180;

function pointPhrase(n: number): string {
  return n === 1 ? "1 point" : `${n} points`;
}

const SYSTEM_PROMPT =
  "You are Sage, a friendly nutrition guide. Write a product OVERVIEW in plain English.\n" +
  "Structure:\n" +
  "1) ONE paragraph (3 to 5 sentences) explaining why the product received its OVERALL score. " +
  "If overallBindingCap is present, LEAD with a plain-language attribution of that health cap " +
  "(concentrated sugar / industrial trans fat / non-nutritive sweetener) and the capped value. " +
  "Treat Top negatives as secondary factors after the cap. " +
  "Otherwise lead with the main drivers from Top positives / Top negatives. " +
  "Use food language only. Reference rules ONLY by their displayName/topic fields from the payload. " +
  "NEVER emit internal rule ids (S1, S2, wholeGrain, flourOxidizers), camelCase tokens, " +
  "'fraction', or internal labels.\n" +
  "Mention concrete facts when provided: detected additive names, avoid-list matches, NOVA group, hardGate.\n" +
  "2) Then 1–2 FINAL sentences on personalization using ONLY the provided deltaValue, " +
  "deltaDrivers, and hardGate (do not invent why the scores differ). " +
  "If hardGate is present and delta is negative, explain THAT binding preference cap only " +
  "(never a non-binding fired cap, and NEVER call overall health caps 'on your list'). " +
  "When intensity is 'partial', say the score was " +
  "'limited' (not 'capped at minimum') and name the driver (e.g. grams of sugar). " +
  "When intensity is 'full', you may say it caps Your Score at cappedTo. " +
  "You may briefly mention other preference firedCaps in one clause. " +
  "Phrase the delta naturally and specifically (name the driver, direction, and point difference). " +
  "When nutrientNudge is nonzero, attribute it using nutrientNudgeDriver " +
  "(e.g. 'slightly adjusted for calorie density given your weight-loss goal'). " +
  "FORBIDDEN: reusing a fixed closing formula such as " +
  "\"weighs degree of processing more heavily, and that's where this product falls short.\" " +
  "Vary the wording every time. Use the exact pointPhrase given (e.g. '1 point', never '1 points'). " +
  "If deltaValue is 0, say the profile didn't change the outcome.\n" +
  "Hard epistemic rules:\n" +
  "- For any rule with evidenceTier 'unknown-tier': NEVER state the product contains/has/presents " +
  "that thing as a measured deficiency (e.g. 'held back by micronutrients'). " +
  "Only describe missing data or assumed uncertainty.\n" +
  "- If hasScoreableIngredientSignal is false OR confidence < 0.80: state early that data is " +
  "limited and the score is provisional.\n" +
  "- If confidence ≥ 0.80 AND every rule is evidenceTier 'data': FORBIDDEN to say " +
  "'where data is thin', 'limited data', 'provisional', or similar.\n" +
  "- Never contradict the displayed nutrient levels. Do not praise sugar/sodium/sat fat when their badge is high.\n" +
  "- Never invent nutrients, additives, packaging, or medical claims.\n" +
  "- Never use em dashes (—) or en dashes (–). Use separate sentences, commas, or parentheses instead.\n" +
  "- Tone: plain, concrete, confident where data is confident. ≤ 90 words. Address the user as 'you'. " +
  "Do not restate overall/your numeric scores.";

const ADDITIVE_PRESENCE_EN = [
  "presence of",
  "contains",
  "has additives",
  "riskier additives",
  "artificial",
  "preservative",
  "emulsifier",
  "thickener",
  "stabilizer",
  "sweetener",
];
const ADDITIVE_PRESENCE_PT = [
  "presença de",
  "contém",
  "aditivos",
  "conservante",
  "espessante",
];
const PACKAGING_CLAIMS = ["packaged in plastic", "plastic packaging", "harmful packaging"];
const THIN_DATA = [
  "data is thin",
  "limited data",
  "provisional",
  "where data is thin",
  "label data is limited",
];

const CAMEL_CASE = /\b[a-z]+[A-Z][a-zA-Z]+\b/;

function knownRuleIds(input: ExplainRequest): string[] {
  if (input.knownRuleIds?.length) return input.knownRuleIds;
  // Client should always send knownRuleIds; fall back to rule ids in this payload.
  return [...new Set((input.rules ?? []).map((r) => r.rule))];
}

function falseListClaim(lower: string, input: ExplainRequest): string | null {
  const allowed = new Set<string>([
    ...(input.avoidMatches ?? []).map((a) => a.toLowerCase()),
    ...(input.hardGate?.shortLabel ? [input.hardGate.shortLabel.toLowerCase()] : []),
    ...(input.firedCaps ?? []).map((c) => c.shortLabel.toLowerCase()),
  ]);
  const patterns = [
    /on your avoid list[^.:]*[: ]+([^.]+)/i,
    /on your list:\s*([^.]+)/i,
    /also on your list:\s*([^.]+)/i,
  ];
  for (const re of patterns) {
    const m = lower.match(re);
    if (!m?.[1]) continue;
    const parts = m[1]
      .split(/[,;]| and /)
      .map((p) => p.replace(/\s+which\b.*/, "").trim())
      .filter(Boolean);
    for (const part of parts) {
      if ([...allowed].some((a) => part.includes(a) || a.includes(part))) continue;
      if (["free sugar", "trans fat", "non-nutritive sweetener"].includes(part)) {
        return `false list claim: ${part}`;
      }
      if (allowed.size > 0 || part === "free sugar") {
        return `false list claim: ${part}`;
      }
    }
  }
  if (lower.includes("on your list") || lower.includes("on your avoid list")) {
    for (const banned of ["free sugar", "trans fat", "non-nutritive sweetener"]) {
      if (lower.includes(banned) && !allowed.has(banned)) {
        return `false list claim: ${banned}`;
      }
    }
  }
  return null;
}

export function validateOverview(text: string, input: ExplainRequest): string | null {
  if (text.includes("\u2014")) return "em dash";
  if (text.includes("\u2013")) return "en dash";

  for (const id of knownRuleIds(input)) {
    // Allow ids that are also legitimate display topics in this payload
    // (e.g. "authenticity" is both a rule id and its prose topic).
    const allowedTopics = new Set([
      ...(input.rules ?? []).map((r) => r.topic),
      ...(input.topPositive ?? []).map((t) => t.topic),
      ...(input.topNegative ?? []).map((t) => t.topic),
    ]);
    if (allowedTopics.has(id)) continue;
    const re = new RegExp(`\\b${id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\b`);
    if (re.test(text)) return id;
  }
  const camel = text.match(CAMEL_CASE);
  if (camel) return camel[0];

  const lower = text.toLowerCase();
  if (!input.hasScoreableIngredientSignal) {
    for (const phrase of [...ADDITIVE_PRESENCE_EN, ...ADDITIVE_PRESENCE_PT]) {
      if (lower.includes(phrase)) return phrase;
    }
    if (/\be\d{3}\b/i.test(text)) return "E-number";
  }
  const s7Unknown = input.rules?.some((r) => r.rule === "S7" && r.evidenceTier === "unknown-tier");
  if (s7Unknown) {
    for (const phrase of PACKAGING_CLAIMS) {
      if (lower.includes(phrase)) return phrase;
    }
  }

  const allData =
    (input.confidence ?? 0) >= 0.8 &&
    !(input.rules ?? []).some((r) => r.evidenceTier === "unknown-tier");
  if (allData) {
    for (const phrase of THIN_DATA) {
      if (lower.includes(phrase)) return phrase;
    }
  }

  const absDelta = Math.abs(input.deltaValue ?? input.your - input.overall);
  if (absDelta === 1 && /\b1 points\b/i.test(text)) return "1 points";

  const overallCap = input.overallBindingCap;
  if (overallCap) {
    const needles: string[] = (() => {
      switch (overallCap.kind) {
        case "freeSugar":
          return [`capped at ${overallCap.value}`, "concentrated sugar", "free sugar", "caloric sweetener"];
        case "transFat":
          return ["trans fat", `capped at ${overallCap.value}`];
        case "nns":
          return ["non-nutritive", `capped at ${overallCap.value}`, "sweetener"];
        default:
          return [`capped at ${overallCap.value}`];
      }
    })();
    if (!needles.some((n) => lower.includes(n.toLowerCase()))) {
      return "overallBindingCap";
    }
  }

  for (const rule of input.rules ?? []) {
    if (rule.evidenceTier !== "unknown-tier") continue;
    const topic = rule.topic.toLowerCase();
    const missingOk =
      lower.includes("missing") ||
      lower.includes("unknown") ||
      lower.includes("can't verify") ||
      lower.includes("cannot verify") ||
      lower.includes("no ") ||
      lower.includes("data is");
    const measuredHit =
      lower.includes(`held back by ${topic}`) ||
      lower.includes(`held back mainly by ${topic}`) ||
      lower.includes(`low ${topic}`) ||
      lower.includes(`limited ${topic}`) ||
      (rule.rule === "S13" &&
        (lower.includes("held back by micronutrient") ||
          lower.includes("limited micronutrient") ||
          lower.includes("low micronutrient")));
    if (measuredHit && !missingOk) return rule.topic;
  }

  const listClaim = falseListClaim(lower, input);
  if (listClaim) return listClaim;

  return null;
}

function englishList(items: string[]): string {
  if (items.length === 0) return "";
  if (items.length === 1) return items[0];
  if (items.length === 2) return `${items[0]} and ${items[1]}`;
  return `${items.slice(0, -1).join(", ")}, and ${items[items.length - 1]}`;
}

function overallCapLead(cap: NonNullable<ExplainRequest["overallBindingCap"]>): string {
  switch (cap.kind) {
    case "freeSugar":
      return `As a concentrated sugar, its score is capped at ${cap.value}.`;
    case "transFat":
      return `It contains industrial trans fat, which caps the overall score at ${cap.value}.`;
    case "nns":
      return `As a non-nutritive sweetener, its score is capped at ${cap.value}.`;
    default:
      return `A health cap limits the overall score at ${cap.value}.`;
  }
}

function negativePhrase(topic: string, input: ExplainRequest): string {
  const rules = input.rules ?? [];
  const match = rules.find((r) => r.topic === topic);
  if (match?.evidenceTier === "unknown-tier") {
    if (topic === "additives" || match.rule === "S1") {
      return "missing ingredient data (the engine can't verify additives, so it assumes uncertainty)";
    }
    if (topic === "packaging" || match.rule === "S7") {
      return "missing packaging data";
    }
    if (match.rule === "S13" || topic.toLowerCase().includes("micronutrient")) {
      return "micronutrient data is missing";
    }
    return `${topic} data is missing`;
  }
  if (topic === "degree of processing") {
    if ((input.novaGroup ?? 0) >= 4) {
      return `degree of processing (ultra-processed, NOVA ${input.novaGroup})`;
    }
    return "degree of processing";
  }
  if (topic === "quality labels") return "no quality certification labels on file";
  if (topic === "certifications") return "no certification labels on file";
  if (topic === "protein and fiber") {
    const levels = (input.nutrientLevels ?? []).map((l) => l.toLowerCase());
    const fiberGood = levels.some(
      (l) => l.startsWith("fiber") && (l.includes("high") || l.includes("good"))
    );
    const proteinOk = levels.some(
      (l) =>
        l.startsWith("protein") &&
        (l.includes("high") || l.includes("good") || l.includes("moderate"))
    );
    if (fiberGood && proteinOk) {
      return "protein and fiber are diluted by calorie density";
    }
    if (
      levels.some((l) => l.startsWith("protein") && (l.includes("high") || l.includes("good"))) ||
      fiberGood
    ) {
      return "protein and fiber are diluted by calorie density";
    }
    return "limited protein and fiber credit";
  }
  return topic;
}

function personalSentence(input: ExplainRequest): string {
  const delta = input.deltaValue ?? input.your - input.overall;
  if (delta === 0) {
    return "Your score matches the overall because your profile didn't change the outcome.";
  }
  const points = pointPhrase(Math.abs(delta));
  const direction = delta < 0 ? "below" : "above";
  const goal = input.objective ?? "goal";
  const gate = input.hardGate;

  if (gate && delta < 0) {
    if (gate.intensity === "partial") {
      return `Your score is ${points} ${direction} the overall because ${gate.detail}.`;
    }
    return `Your score is ${points} ${direction} the overall because this product ${gate.detail}.`;
  }

  const drivers = input.deltaDrivers ?? [];
  if (drivers.length === 0) {
    return `Your score is ${points} ${direction} the overall from how your "${goal}" goal reweights the rules.`;
  }
  const down = drivers.filter((d) => d.direction === "down").map((d) => d.topic);
  const up = drivers.filter((d) => d.direction === "up").map((d) => d.topic);
  const variant = Math.abs(delta + input.overall + input.your) % 3;

  if (delta < 0 && down.length) {
    if (variant === 0) {
      return `Your score is ${points} ${direction} the overall: your "${goal}" goal puts more weight on ${englishList(down)}, which pulls this product down.`;
    }
    if (variant === 1) {
      return `Relative to overall, you're ${points} ${direction} because "${goal}" emphasizes ${englishList(down)}.`;
    }
    return `The ${points} drop vs overall comes from "${goal}" stressing ${englishList(down)}, where this product loses ground.`;
  }
  if (delta > 0 && up.length) {
    if (variant === 0) {
      return `Your score is ${points} ${direction} the overall because "${goal}" emphasizes ${englishList(up)}, where this product does better.`;
    }
    if (variant === 1) {
      return `You're ${points} ${direction} overall: "${goal}" boosts ${englishList(up)} for this product.`;
    }
    return `The ${points} lift vs overall tracks "${goal}" and stronger ${englishList(up)}.`;
  }
  return `Your score is ${points} ${direction} the overall because your "${goal}" goal weighs ${englishList(drivers.map((d) => d.topic))} differently.`;
}

export function buildTemplateOverview(input: ExplainRequest): string {
  const parts: string[] = [];
  const limited =
    !input.hasScoreableIngredientSignal ||
    (input.confidence ?? 0) < 0.8 ||
    (input.rules ?? []).some((r) => r.weight >= 10 && r.evidenceTier === "unknown-tier");
  if (limited) {
    parts.push("Label data is limited, so treat this score as provisional.");
  }

  const positives = (input.topPositive ?? []).map((t) => t.topic);
  const negatives = (input.topNegative ?? []).map((t) => t.topic);

  if (input.overallBindingCap) {
    parts.push(overallCapLead(input.overallBindingCap));
    if (negatives.length) {
      const phrases = negatives.map((t) => negativePhrase(t, input));
      parts.push(`Secondary factors include ${englishList(phrases)}.`);
    }
  } else {
    if (positives.length) {
      parts.push(`It scores well on ${englishList(positives)}.`);
    }
    if (negatives.length) {
      const phrases = negatives.map((t) => negativePhrase(t, input));
      parts.push(`The score is held back mainly by ${englishList(phrases)}.`);
    } else {
      parts.push("Nothing major held the overall score back in the data we have.");
    }
  }

  if ((input.novaGroup ?? 0) >= 4 && !negatives.some((t) => t.includes("processing"))) {
    parts.push(`It's ultra-processed (NOVA ${input.novaGroup}).`);
  }

  if (input.avoidMatches?.length) {
    const items = englishList(input.avoidMatches.map((a) => a.toLowerCase()));
    const verb = input.avoidMatches.length === 1 ? "is" : "are";
    parts.push(`It also contains ${items}, which ${verb} on your avoid list.`);
  }

  return `${parts.join(" ")} ${personalSentence(input)}`.trim();
}

function buildPrompt(input: ExplainRequest, violation?: string): string {
  const delta = input.deltaValue ?? input.your - input.overall;
  const lines = [
    `Product: ${input.productName ?? "this product"}`,
    `Goal: ${input.objective ?? "maintain"}`,
    `Overall score band: ${input.band ?? "unknown"}`,
    `Confidence: ${((input.confidence ?? 0) * 100).toFixed(1)}%`,
    `hasScoreableIngredientSignal: ${input.hasScoreableIngredientSignal}`,
    `hasIngredientData: ${input.hasIngredientData}`,
    `hasNutritionData: ${input.hasNutritionData}`,
    `NOVA group: ${input.novaGroup ?? "unknown"}`,
    `Detected additives: ${(input.detectedAdditives ?? []).join(", ") || "none"}`,
    `Avoid-list matches: ${(input.avoidMatches ?? []).join(", ") || "none"}`,
    `hardGate (preference binding only): ${
      input.hardGate
        ? `${input.hardGate.kind}/${input.hardGate.intensity ?? "full"} - ${input.hardGate.detail} (cap ${input.hardGate.cappedTo})`
        : "none"
    }`,
    `bindingCap (preference): ${
      input.bindingCap
        ? `${input.bindingCap.id}=${input.bindingCap.value} (${input.bindingCap.shortLabel})`
        : "none"
    }`,
    `firedCaps (preference): ${
      (input.firedCaps ?? [])
        .map((c) => `${c.id}=${c.value}`)
        .join(", ") || "none"
    }`,
    `overallBindingCap: ${
      input.overallBindingCap
        ? `${input.overallBindingCap.id}=${input.overallBindingCap.value} (${input.overallBindingCap.kind})`
        : "none"
    }`,
    `overallFiredCaps: ${
      (input.overallFiredCaps ?? [])
        .map((c) => `${c.id}=${c.value}`)
        .join(", ") || "none"
    }`,
    `nutrientNudge: ${input.nutrientNudge ?? 0}`,
    `nutrientNudgeDriver: ${input.nutrientNudgeDriver ?? "none"}`,
    "",
    "Rules (use topic/displayName only in prose; weight × fraction = contribution; evidenceTier is authoritative):",
    ...(input.rules ?? []).map(
      (r) =>
        `- ${r.topic} [id=${r.rule}, kind=${r.driverKind ?? "merit"}]: w=${r.weight} f=${r.fraction.toFixed(3)} contrib=${r.contribution.toFixed(2)} tier=${r.evidenceTier}` +
        (r.multiplier != null && r.multiplier !== 1 ? ` mult=${r.multiplier.toFixed(2)}` : "")
    ),
    "",
    `Top positives (merit only): ${(input.topPositive ?? []).map((t) => t.topic).join(", ") || "none"}`,
    `Top negatives (by potential loss w×m×(1−f), floor 2.0): ${(input.topNegative ?? []).map((t) => t.topic).join(", ") || "none"}`,
    `deltaValue: ${delta} (pointPhrase: "${pointPhrase(Math.abs(delta))}")`,
    `deltaDrivers (state ONLY these): ${
      (input.deltaDrivers ?? [])
        .map((d) => `${d.topic}→${d.direction}`)
        .join(", ") || "none (scores match)"
    }`,
  ];
  if (input.nutrientLevels?.length) {
    lines.push(`Displayed nutrient levels (must agree): ${input.nutrientLevels.join("; ")}`);
  }
  if (violation) {
    lines.push("");
    lines.push(
      `REJECTED prior draft; violation "${violation}". Rewrite fixing that exact issue.`
    );
  }
  lines.push("");
  lines.push("Write the overview (≤90 words).");
  return lines.join("\n");
}

async function callLLM(env: Env, userPrompt: string): Promise<string | null> {
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
      temperature: 0.35,
      messages: [
        { role: "system", content: SYSTEM_PROMPT },
        { role: "user", content: userPrompt },
      ],
    }),
  });

  if (!res.ok) return null;
  const data = (await res.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  return data.choices?.[0]?.message?.content?.trim() ?? null;
}

export async function generateExplanation(env: Env, input: ExplainRequest): Promise<string> {
  const draft = await callLLM(env, buildPrompt(input));
  if (draft) {
    const violation = validateOverview(draft, input);
    if (!violation) return draft;

    console.warn(`overview validator rejected: ${violation}`);
    const retry = await callLLM(env, buildPrompt(input, violation));
    if (retry && !validateOverview(retry, input)) return retry;
  }

  return buildTemplateOverview(input);
}

export type { OverviewContext };
