export const CONTRACT_VERSION = 1;
export const MAX_RAW_REQUEST_BYTES = 64 * 1024;
export const HARD_MAX_INPUT_CHARS = 8_000;
export const HARD_MAX_HISTORY_MESSAGES = 40;
export const HARD_MAX_HISTORY_CHARS = 40_000;
export const HARD_MAX_OUTPUT_CHARS = 32_000;
export const HARD_MAX_PROVIDER_TIMEOUT_MS = 60_000;

export type SupportedLocale = "en" | "ar";
export type Operation = "bootstrap" | "accept_disclosure" | "chat";
export type MessageRole = "user" | "assistant";

export interface ClientInfo {
  platform: "android";
  version: string;
  build: number;
  locale: SupportedLocale;
}

export interface ChatMessage {
  role: MessageRole;
  content: string;
}

export interface ValidatedRequest {
  contractVersion: 1;
  operation: Operation;
  client: ClientInfo;
  requestId?: string;
  disclosureVersion?: string;
  messages?: ChatMessage[];
}

export interface RuntimeConfig {
  contractVersion: number;
  configVersion: number;
  visible: boolean;
  enabled: boolean;
  maintenanceMode: boolean;
  providerKind: "cliproxyapi";
  providerBaseUrl: string;
  providerApiPath: "/v1/responses";
  primaryModel: string;
  fallbackModels: string[];
  activePromptVersion: string;
  maxInputChars: number;
  maxHistoryMessages: number;
  maxHistoryChars: number;
  maxOutputTokens: number;
  providerTimeoutMs: number;
  transportRetryCount: number;
  dailyRequestLimit: number;
  burstRequestLimit: number;
  burstWindowSeconds: number;
  rolloutPercentage: number;
  rolloutSalt: string;
  minClientBuild: number;
  maxClientBuild: number | null;
  disclosureVersion: string;
  disclosureRequired: boolean;
  circuitFailureThreshold: number;
  circuitCooldownSeconds: number;
  usageRetentionDays: number;
}

export interface RuntimeSnapshot {
  config: RuntimeConfig;
  prompt: {
    version: string;
    locale: string;
    instructions: string;
    enabled: boolean;
  };
  localizedContent: Record<string, string>;
  suggestions: Array<{ key: string; title: string; prompt: string }>;
  allowlisted: boolean;
  disclosureAccepted: boolean;
  quota: {
    dailyCount: number;
    burstCount: number;
    dailyResetsAt: string;
    burstResetsAt: string;
  };
  providerHealth: {
    state: "closed" | "open" | "half_open" | "unconfigured";
    cooldown_until?: string | null;
  } | null;
}

export interface QuotaClaim {
  status:
    | "claimed"
    | "duplicate_in_progress"
    | "duplicate_completed"
    | "daily_limit_reached"
    | "burst_limit_reached";
  dailyRemaining?: number;
  burstRemaining?: number;
  dailyResetsAt?: string;
  burstResetsAt?: string;
  retryAfterSeconds?: number;
}

export interface ProviderChatRequest {
  model: string;
  instructions: string;
  messages: ChatMessage[];
  maxOutputTokens: number;
  timeoutMs: number;
  gatewaySecret: string;
  apiKey: string;
  endpoint: URL;
}

export interface ProviderChatResult {
  text: string;
  promptTokens?: number;
  completionTokens?: number;
}
