import { HARD_MAX_OUTPUT_CHARS } from "./contracts.ts";
import { AiChatError } from "./errors.ts";

function nonEmptyText(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const text = value.trim();
  return text.length === 0 ? null : text;
}

export function parseProviderResponse(value: unknown): {
  text: string;
  promptTokens?: number;
  completionTokens?: number;
} {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new AiChatError("invalid_provider_response");
  }
  const object = value as Record<string, unknown>;
  let text = nonEmptyText(object.output_text);
  if (text === null && Array.isArray(object.output)) {
    const chunks: string[] = [];
    for (const item of object.output) {
      if (item === null || typeof item !== "object" || Array.isArray(item)) continue;
      const content = (item as Record<string, unknown>).content;
      if (!Array.isArray(content)) continue;
      for (const entry of content) {
        if (entry === null || typeof entry !== "object" || Array.isArray(entry)) continue;
        const part = entry as Record<string, unknown>;
        if (part.type === "output_text") {
          const candidate = nonEmptyText(part.text);
          if (candidate !== null) chunks.push(candidate);
        }
      }
    }
    text = chunks.length > 0 ? chunks.join("\n") : null;
  }
  if (text === null || text.length > HARD_MAX_OUTPUT_CHARS) {
    throw new AiChatError("invalid_provider_response");
  }
  const usage = object.usage;
  const usageObject = usage && typeof usage === "object" && !Array.isArray(usage)
    ? usage as Record<string, unknown>
    : {};
  return {
    text,
    promptTokens: Number.isSafeInteger(usageObject.input_tokens) ? Number(usageObject.input_tokens) : undefined,
    completionTokens: Number.isSafeInteger(usageObject.output_tokens) ? Number(usageObject.output_tokens) : undefined,
  };
}
