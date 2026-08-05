import type { SupabaseClient } from "@supabase/supabase-js";
import type { QuotaClaim, RuntimeConfig, RuntimeSnapshot } from "./contracts.ts";
import { AiChatError } from "./errors.ts";

export interface ProviderAccessClaim {
  allowed: boolean;
  probe: boolean;
  state: "closed" | "open" | "half_open" | "unconfigured";
  retryAfterSeconds?: number;
}

export interface GatewayRepository {
  loadSnapshot(locale: string, clientBuild: number, userId: string): Promise<RuntimeSnapshot>;
  acceptDisclosure(userId: string, version: string, clientBuild: number, locale: string): Promise<boolean>;
  claimProviderAccess(providerKind: string, now: Date, probeLeaseSeconds: number): Promise<ProviderAccessClaim>;
  claimRequest(args: {
    userId: string;
    requestId: string;
    config: RuntimeConfig;
    model: string;
    inputChars: number;
    historyMessages: number;
    now: Date;
  }): Promise<QuotaClaim>;
  completeRequest(args: {
    userId: string;
    requestId: string;
    status: "completed" | "failed";
    model: string;
    latencyMs: number;
    outputChars: number | null;
    promptTokens: number | null;
    completionTokens: number | null;
    errorCode: string | null;
    completedAt: Date;
  }): Promise<void>;
  recordProviderResult(args: {
    config: RuntimeConfig;
    success: boolean;
    retryableFailure: boolean;
    errorCode: string | null;
    latencyMs: number;
    now: Date;
  }): Promise<void>;
}

function expectRecord(value: unknown): Record<string, unknown> {
  if (value === null || typeof value !== "object" || Array.isArray(value)) {
    throw new AiChatError("server_configuration_error");
  }
  return value as Record<string, unknown>;
}

function integer(value: unknown): number {
  if (!Number.isSafeInteger(value)) throw new AiChatError("server_configuration_error");
  return Number(value);
}

function runtimeConfig(value: unknown): RuntimeConfig {
  const raw = expectRecord(value);
  const fallback = raw.fallback_models;
  if (!Array.isArray(fallback) || fallback.length > 4 || fallback.some((item) => typeof item !== "string")) {
    throw new AiChatError("server_configuration_error");
  }
  if (raw.provider_kind !== "cliproxyapi" || raw.provider_api_path !== "/v1/responses") {
    throw new AiChatError("server_configuration_error");
  }
  const config: RuntimeConfig = {
    contractVersion: integer(raw.contract_version),
    configVersion: integer(raw.config_version),
    visible: raw.visible === true,
    enabled: raw.enabled === true,
    maintenanceMode: raw.maintenance_mode === true,
    providerKind: "cliproxyapi",
    providerBaseUrl: typeof raw.provider_base_url === "string" ? raw.provider_base_url : "",
    providerApiPath: "/v1/responses",
    primaryModel: typeof raw.primary_model === "string" ? raw.primary_model.trim() : "",
    fallbackModels: (fallback as string[]).map((value) => value.trim()).filter(Boolean),
    activePromptVersion: typeof raw.active_prompt_version === "string" ? raw.active_prompt_version : "",
    maxInputChars: integer(raw.max_input_chars),
    maxHistoryMessages: integer(raw.max_history_messages),
    maxHistoryChars: integer(raw.max_history_chars),
    maxOutputTokens: integer(raw.max_output_tokens),
    providerTimeoutMs: integer(raw.provider_timeout_ms),
    transportRetryCount: integer(raw.transport_retry_count),
    dailyRequestLimit: integer(raw.daily_request_limit),
    burstRequestLimit: integer(raw.burst_request_limit),
    burstWindowSeconds: integer(raw.burst_window_seconds),
    rolloutPercentage: integer(raw.rollout_percentage),
    rolloutSalt: typeof raw.rollout_salt === "string" ? raw.rollout_salt : "",
    minClientBuild: integer(raw.min_client_build),
    maxClientBuild: raw.max_client_build === null ? null : integer(raw.max_client_build),
    disclosureVersion: typeof raw.disclosure_version === "string" ? raw.disclosure_version : "",
    disclosureRequired: raw.disclosure_required === true,
    circuitFailureThreshold: integer(raw.circuit_failure_threshold),
    circuitCooldownSeconds: integer(raw.circuit_cooldown_seconds),
    usageRetentionDays: integer(raw.usage_retention_days),
  };
  let endpoint: URL;
  try {
    endpoint = new URL(config.providerBaseUrl);
  } catch {
    throw new AiChatError("server_configuration_error");
  }
  if (
    endpoint.protocol !== "https:" || endpoint.username || endpoint.password ||
    endpoint.search || endpoint.hash || endpoint.pathname !== "/"
  ) {
    throw new AiChatError("server_configuration_error");
  }
  if (
    config.contractVersion !== 1 || config.configVersion < 1 ||
    config.primaryModel.length === 0 || config.rolloutSalt.trim().length < 16 ||
    config.transportRetryCount < 0 || config.transportRetryCount > 1
  ) {
    throw new AiChatError("server_configuration_error");
  }
  return config;
}

function quotaClaim(value: unknown): QuotaClaim {
  const raw = expectRecord(value);
  const status = raw.status;
  if (
    status !== "claimed" && status !== "duplicate_in_progress" &&
    status !== "duplicate_completed" && status !== "daily_limit_reached" &&
    status !== "burst_limit_reached"
  ) {
    throw new AiChatError("internal_error");
  }
  return {
    status,
    dailyRemaining: Number.isSafeInteger(raw.dailyRemaining) ? Number(raw.dailyRemaining) : undefined,
    burstRemaining: Number.isSafeInteger(raw.burstRemaining) ? Number(raw.burstRemaining) : undefined,
    dailyResetsAt: typeof raw.dailyResetsAt === "string" ? raw.dailyResetsAt : undefined,
    burstResetsAt: typeof raw.burstResetsAt === "string" ? raw.burstResetsAt : undefined,
    retryAfterSeconds: Number.isSafeInteger(raw.retryAfterSeconds) ? Number(raw.retryAfterSeconds) : undefined,
  };
}

export class SupabaseGatewayRepository implements GatewayRepository {
  constructor(private readonly adminClient: SupabaseClient) {}

  async loadSnapshot(locale: string, clientBuild: number, userId: string): Promise<RuntimeSnapshot> {
    const { data, error } = await this.adminClient.rpc("get_ai_chat_runtime_config", {
      p_locale: locale,
      p_client_build: clientBuild,
      p_user_id: userId,
    });
    if (error) throw new AiChatError("server_configuration_error");
    const raw = expectRecord(data);
    const prompt = expectRecord(raw.prompt);
    const quota = expectRecord(raw.quota);
    const health = raw.providerHealth === null ? null : expectRecord(raw.providerHealth);
    const localized = expectRecord(raw.localizedContent);
    const suggestions = Array.isArray(raw.suggestions) ? raw.suggestions : [];
    return {
      config: runtimeConfig(raw.config),
      prompt: {
        version: typeof prompt.version === "string" ? prompt.version : "",
        locale: typeof prompt.locale === "string" ? prompt.locale : "",
        instructions: typeof prompt.instructions === "string" ? prompt.instructions : "",
        enabled: prompt.enabled === true,
      },
      localizedContent: Object.fromEntries(
        Object.entries(localized).filter((entry): entry is [string, string] => typeof entry[1] === "string"),
      ),
      suggestions: suggestions.flatMap((item) => {
        if (item === null || typeof item !== "object" || Array.isArray(item)) return [];
        const value = item as Record<string, unknown>;
        return typeof value.key === "string" && typeof value.title === "string" && typeof value.prompt === "string"
          ? [{ key: value.key, title: value.title, prompt: value.prompt }]
          : [];
      }),
      allowlisted: raw.allowlisted === true,
      disclosureAccepted: raw.disclosureAccepted === true,
      quota: {
        dailyCount: integer(quota.dailyCount),
        burstCount: integer(quota.burstCount),
        dailyResetsAt: String(quota.dailyResetsAt),
        burstResetsAt: String(quota.burstResetsAt),
      },
      providerHealth: health === null ? null : {
        state: health.state === "closed" || health.state === "open" ||
            health.state === "half_open" || health.state === "unconfigured"
          ? health.state
          : "unconfigured",
        cooldown_until: typeof health.cooldown_until === "string" ? health.cooldown_until : null,
      },
    };
  }

  async acceptDisclosure(userId: string, version: string, clientBuild: number, locale: string): Promise<boolean> {
    const { data, error } = await this.adminClient.rpc("accept_ai_chat_disclosure", {
      p_user_id: userId,
      p_disclosure_version: version,
      p_client_build: clientBuild,
      p_locale: locale,
    });
    if (error) throw new AiChatError("internal_error");
    return data === true;
  }

  async claimProviderAccess(
    providerKind: string,
    now: Date,
    probeLeaseSeconds: number,
  ): Promise<ProviderAccessClaim> {
    const { data, error } = await this.adminClient.rpc("claim_ai_chat_provider_access", {
      p_provider_kind: providerKind,
      p_now: now.toISOString(),
      p_probe_lease_seconds: probeLeaseSeconds,
    });
    if (error) throw new AiChatError("internal_error");
    const raw = expectRecord(data);
    const state = raw.state;
    if (state !== "closed" && state !== "open" && state !== "half_open" && state !== "unconfigured") {
      throw new AiChatError("internal_error");
    }
    return {
      allowed: raw.allowed === true,
      probe: raw.probe === true,
      state,
      retryAfterSeconds: Number.isSafeInteger(raw.retryAfterSeconds)
        ? Number(raw.retryAfterSeconds)
        : undefined,
    };
  }

  async claimRequest(args: Parameters<GatewayRepository["claimRequest"]>[0]): Promise<QuotaClaim> {
    const { data, error } = await this.adminClient.rpc("claim_ai_chat_request", {
      p_user_id: args.userId,
      p_request_id: args.requestId,
      p_config_version: args.config.configVersion,
      p_provider_kind: args.config.providerKind,
      p_model: args.model,
      p_input_chars: args.inputChars,
      p_history_messages: args.historyMessages,
      p_now: args.now.toISOString(),
      p_daily_limit: args.config.dailyRequestLimit,
      p_burst_limit: args.config.burstRequestLimit,
      p_burst_window_seconds: args.config.burstWindowSeconds,
    });
    if (error) throw new AiChatError("internal_error");
    return quotaClaim(data);
  }

  async completeRequest(args: Parameters<GatewayRepository["completeRequest"]>[0]): Promise<void> {
    const { data, error } = await this.adminClient.rpc("complete_ai_chat_request", {
      p_user_id: args.userId,
      p_request_id: args.requestId,
      p_status: args.status,
      p_model: args.model,
      p_latency_ms: args.latencyMs,
      p_output_chars: args.outputChars,
      p_prompt_tokens: args.promptTokens,
      p_completion_tokens: args.completionTokens,
      p_error_code: args.errorCode,
      p_completed_at: args.completedAt.toISOString(),
    });
    if (error || data !== true) throw new AiChatError("internal_error");
  }

  async recordProviderResult(args: Parameters<GatewayRepository["recordProviderResult"]>[0]): Promise<void> {
    const { error } = await this.adminClient.rpc("record_ai_chat_provider_result", {
      p_provider_kind: args.config.providerKind,
      p_success: args.success,
      p_retryable_failure: args.retryableFailure,
      p_error_code: args.errorCode,
      p_latency_ms: args.latencyMs,
      p_failure_threshold: args.config.circuitFailureThreshold,
      p_cooldown_seconds: args.config.circuitCooldownSeconds,
      p_now: args.now.toISOString(),
    });
    if (error) throw new AiChatError("internal_error");
  }
}
