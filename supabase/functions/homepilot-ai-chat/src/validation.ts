import {
  CONTRACT_VERSION,
  HARD_MAX_HISTORY_CHARS,
  HARD_MAX_HISTORY_MESSAGES,
  HARD_MAX_INPUT_CHARS,
  type ChatMessage,
  type ClientInfo,
  type Operation,
  type ValidatedRequest,
} from "./contracts.ts";
import { AiChatError } from "./errors.ts";

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const VERSION_RE = /^[0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?$/;
const TOP_LEVEL_FIELDS = new Set([
  "contractVersion",
  "operation",
  "client",
  "requestId",
  "disclosureVersion",
  "messages",
]);
const CLIENT_FIELDS = new Set(["platform", "version", "build", "locale"]);
const MESSAGE_FIELDS = new Set(["role", "content"]);

function objectValue(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new AiChatError("invalid_request");
  }
  return value as Record<string, unknown>;
}

function rejectUnknownKeys(value: Record<string, unknown>, allowed: Set<string>): void {
  if (Object.keys(value).some((key) => !allowed.has(key))) {
    throw new AiChatError("invalid_request");
  }
}

function clientInfo(value: unknown): ClientInfo {
  const client = objectValue(value);
  rejectUnknownKeys(client, CLIENT_FIELDS);
  if (client.platform !== "android") throw new AiChatError("invalid_request");
  if (typeof client.version !== "string" || client.version.length > 50 || !VERSION_RE.test(client.version)) {
    throw new AiChatError("invalid_request");
  }
  if (!Number.isSafeInteger(client.build) || Number(client.build) <= 0) {
    throw new AiChatError("invalid_request");
  }
  if (client.locale !== "en" && client.locale !== "ar") {
    throw new AiChatError("invalid_request");
  }
  return {
    platform: "android",
    version: client.version,
    build: Number(client.build),
    locale: client.locale,
  };
}

function messages(value: unknown): ChatMessage[] {
  if (!Array.isArray(value) || value.length === 0 || value.length > HARD_MAX_HISTORY_MESSAGES) {
    throw new AiChatError("invalid_request");
  }
  const result: ChatMessage[] = value.map((raw): ChatMessage => {
    const message = objectValue(raw);
    rejectUnknownKeys(message, MESSAGE_FIELDS);
    if (message.role !== "user" && message.role !== "assistant") {
      throw new AiChatError("invalid_request");
    }
    if (typeof message.content !== "string" || message.content.length === 0) {
      throw new AiChatError("invalid_request");
    }
    if (message.content.length > HARD_MAX_INPUT_CHARS) {
      throw new AiChatError("input_too_long");
    }
    return { role: message.role, content: message.content };
  });
  if (result[0]?.role !== "user" || result[result.length - 1]?.role !== "user") {
    throw new AiChatError("invalid_request");
  }
  if (result.reduce((total, item) => total + item.content.length, 0) > HARD_MAX_HISTORY_CHARS) {
    throw new AiChatError("history_too_large");
  }
  return result;
}

export function validateRequest(value: unknown): ValidatedRequest {
  const envelope = objectValue(value);
  rejectUnknownKeys(envelope, TOP_LEVEL_FIELDS);
  if (envelope.contractVersion !== CONTRACT_VERSION) {
    throw new AiChatError("unsupported_contract");
  }
  const operation = envelope.operation;
  if (operation !== "bootstrap" && operation !== "accept_disclosure" && operation !== "chat") {
    throw new AiChatError("invalid_request");
  }
  const result: ValidatedRequest = {
    contractVersion: CONTRACT_VERSION,
    operation: operation as Operation,
    client: clientInfo(envelope.client),
  };
  if (operation === "bootstrap") {
    if (envelope.requestId !== undefined || envelope.disclosureVersion !== undefined || envelope.messages !== undefined) {
      throw new AiChatError("invalid_request");
    }
    return result;
  }
  if (operation === "accept_disclosure") {
    if (typeof envelope.disclosureVersion !== "string" || envelope.disclosureVersion.length > 200) {
      throw new AiChatError("invalid_request");
    }
    if (envelope.requestId !== undefined || envelope.messages !== undefined) {
      throw new AiChatError("invalid_request");
    }
    return { ...result, disclosureVersion: envelope.disclosureVersion };
  }
  if (typeof envelope.requestId !== "string" || !UUID_RE.test(envelope.requestId)) {
    throw new AiChatError("invalid_request");
  }
  if (envelope.disclosureVersion !== undefined) throw new AiChatError("invalid_request");
  return { ...result, requestId: envelope.requestId, messages: messages(envelope.messages) };
}

export function validateAgainstRuntime(
  request: ValidatedRequest,
  maxInputChars: number,
  maxHistoryMessages: number,
  maxHistoryChars: number,
): void {
  if (request.operation !== "chat") return;
  const chatMessages = request.messages ?? [];
  if (chatMessages.length > maxHistoryMessages) throw new AiChatError("history_too_large");
  if (chatMessages.reduce((sum, item) => sum + item.content.length, 0) > maxHistoryChars) {
    throw new AiChatError("history_too_large");
  }
  const finalMessage = chatMessages[chatMessages.length - 1];
  if (!finalMessage || finalMessage.content.trim().length === 0) throw new AiChatError("invalid_request");
  if (finalMessage.content.length > maxInputChars) throw new AiChatError("input_too_long");
}
