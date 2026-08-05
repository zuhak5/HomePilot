import {
  HARD_MAX_PROVIDER_TIMEOUT_MS,
  MAX_RAW_REQUEST_BYTES,
  type RuntimeSnapshot,
  type ValidatedRequest,
} from "./contracts.ts";
import { AiChatError, errorResponse } from "./errors.ts";
import type { SafeLogger } from "./logging.ts";
import type { AiChatProvider } from "./provider.ts";
import type { GatewayRepository } from "./repositories.ts";
import { isAssignedToRollout } from "./rollout.ts";
import { validateAgainstRuntime, validateRequest } from "./validation.ts";

export interface ProviderCredentials {
  apiKey: string;
  gatewaySecret: string;
}

export interface HandlerDependencies {
  authenticatedUserId: string;
  repository: GatewayRepository;
  provider: AiChatProvider;
  providerCredentials: () => ProviderCredentials;
  logger: SafeLogger;
  now: () => Date;
}

function jsonResponse(value: unknown, status = 200): Response {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function content(snapshot: RuntimeSnapshot, key: string): string | null {
  const value = snapshot.localizedContent[key];
  return typeof value === "string" && value.trim().length > 0 ? value : null;
}

function featureState(
  snapshot: RuntimeSnapshot,
  request: ValidatedRequest,
): { state: string; message: string | null } {
  const config = snapshot.config;
  if (!config.visible) return { state: "hidden", message: null };
  if (!config.enabled) return { state: "disabled", message: content(snapshot, "disabled_message") };
  if (config.maintenanceMode) {
    return { state: "maintenance", message: content(snapshot, "maintenance_message") };
  }
  if (
    request.client.build < config.minClientBuild ||
    (config.maxClientBuild !== null && request.client.build > config.maxClientBuild)
  ) {
    return {
      state: "unsupported_app_version",
      message: content(snapshot, "unsupported_version_message"),
    };
  }
  return { state: "ready", message: null };
}

async function enforceAvailability(
  snapshot: RuntimeSnapshot,
  request: ValidatedRequest,
  userId: string,
): Promise<void> {
  const state = featureState(snapshot, request).state;
  if (state === "hidden") throw new AiChatError("feature_hidden");
  if (state === "disabled") throw new AiChatError("feature_disabled");
  if (state === "maintenance") throw new AiChatError("maintenance");
  if (state === "unsupported_app_version") {
    throw new AiChatError("unsupported_app_version");
  }
  const assigned = snapshot.allowlisted || await isAssignedToRollout(
    userId,
    snapshot.config.rolloutSalt,
    snapshot.config.rolloutPercentage,
  );
  if (!assigned) throw new AiChatError("rollout_unavailable");
}

function sanitizedBootstrap(
  snapshot: RuntimeSnapshot,
  request: ValidatedRequest,
  available: boolean,
  state: string,
) {
  const config = snapshot.config;
  return {
    contractVersion: 1,
    configVersion: config.configVersion,
    feature: {
      visible: config.visible,
      available,
      state,
      message: featureState(snapshot, request).message ??
        (state === "rollout_unavailable"
          ? content(snapshot, "rollout_unavailable_message")
          : null),
    },
    limits: {
      maxInputChars: config.maxInputChars,
      maxHistoryMessages: config.maxHistoryMessages,
      maxHistoryChars: config.maxHistoryChars,
    },
    quota: {
      dailyRemaining: Math.max(0, config.dailyRequestLimit - snapshot.quota.dailyCount),
      burstRemaining: Math.max(0, config.burstRequestLimit - snapshot.quota.burstCount),
      resetsAt: snapshot.quota.dailyResetsAt,
    },
    suggestions: snapshot.suggestions,
    disclosure: {
      required: config.disclosureRequired && !snapshot.disclosureAccepted,
      version: config.disclosureVersion,
      title: content(snapshot, "disclosure_title"),
      body: content(snapshot, "disclosure_body"),
    },
    serviceDisclaimer: content(snapshot, "service_disclaimer"),
    localizedContent: {
      welcome_message: content(snapshot, "welcome_message"),
    },
  };
}

function providerError(error: unknown): AiChatError {
  return error instanceof AiChatError ? error : new AiChatError("provider_unavailable");
}

function canRetryTransport(error: AiChatError): boolean {
  return error.code === "provider_unavailable";
}

export function createHandler(deps: HandlerDependencies): (request: Request) => Promise<Response> {
  return async (request: Request): Promise<Response> => {
    const startedAt = deps.now();
    let requestId: string | null = null;
    let operation = "unknown";
    try {
      if (request.method !== "POST") throw new AiChatError("method_not_allowed");
      const contentType = request.headers.get("Content-Type")?.toLowerCase() ?? "";
      if (!contentType.startsWith("application/json")) {
        throw new AiChatError("unsupported_media_type");
      }
      const declaredLength = Number(request.headers.get("Content-Length") ?? 0);
      if (Number.isFinite(declaredLength) && declaredLength > MAX_RAW_REQUEST_BYTES) {
        throw new AiChatError("request_too_large");
      }
      const rawBody = await request.text();
      if (new TextEncoder().encode(rawBody).byteLength > MAX_RAW_REQUEST_BYTES) {
        throw new AiChatError("request_too_large");
      }
      let payload: unknown;
      try {
        payload = JSON.parse(rawBody);
      } catch {
        throw new AiChatError("invalid_json");
      }
      const validated = validateRequest(payload);
      operation = validated.operation;
      requestId = validated.requestId ?? null;
      const userId = deps.authenticatedUserId;
      if (!userId) throw new AiChatError("session_invalid");

      const snapshot = await deps.repository.loadSnapshot(
        validated.client.locale,
        validated.client.build,
        userId,
      );
      if (snapshot.config.contractVersion !== 1) {
        throw new AiChatError("unsupported_contract");
      }

      if (validated.operation === "bootstrap") {
        const baseState = featureState(snapshot, validated).state;
        let available = baseState === "ready";
        let state = baseState;
        if (available) {
          const assigned = snapshot.allowlisted || await isAssignedToRollout(
            userId,
            snapshot.config.rolloutSalt,
            snapshot.config.rolloutPercentage,
          );
          if (!assigned) {
            available = false;
            state = "rollout_unavailable";
          }
        }
        const response = sanitizedBootstrap(snapshot, validated, available, state);
        deps.logger.info({
          operation,
          requestId,
          contractVersion: 1,
          configVersion: snapshot.config.configVersion,
          outcome: state,
          status: 200,
          locale: validated.client.locale,
        });
        return jsonResponse({ ...response, serverTime: deps.now().toISOString() });
      }

      await enforceAvailability(snapshot, validated, userId);
      if (validated.operation === "accept_disclosure") {
        if (validated.disclosureVersion !== snapshot.config.disclosureVersion) {
          throw new AiChatError("invalid_request");
        }
        const accepted = await deps.repository.acceptDisclosure(
          userId,
          validated.disclosureVersion,
          validated.client.build,
          validated.client.locale,
        );
        if (!accepted) throw new AiChatError("invalid_request");
        deps.logger.info({
          operation,
          requestId,
          contractVersion: 1,
          configVersion: snapshot.config.configVersion,
          outcome: "accepted",
          status: 204,
          locale: validated.client.locale,
        });
        return new Response(null, {
          status: 204,
          headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" },
        });
      }

      if (snapshot.config.disclosureRequired && !snapshot.disclosureAccepted) {
        throw new AiChatError("disclosure_required");
      }
      if (
        !snapshot.prompt.enabled || snapshot.prompt.instructions.trim().length === 0 ||
        snapshot.config.activePromptVersion === "unconfigured-v1"
      ) {
        throw new AiChatError("server_configuration_error");
      }
      validateAgainstRuntime(
        validated,
        snapshot.config.maxInputChars,
        snapshot.config.maxHistoryMessages,
        snapshot.config.maxHistoryChars,
      );
      const models = [snapshot.config.primaryModel, ...snapshot.config.fallbackModels]
        .map((model) => model.trim())
        .filter((model, index, all) => model.length > 0 && all.indexOf(model) === index)
        .slice(0, 5);
      const selectedModel = models[0];
      if (!selectedModel || selectedModel === "unconfigured") {
        throw new AiChatError("server_configuration_error");
      }
      const credentials = deps.providerCredentials();
      if (!credentials.apiKey.trim() || !credentials.gatewaySecret.trim()) {
        throw new AiChatError("server_configuration_error");
      }

      const messages = validated.messages ?? [];
      const inputChars = messages.reduce((sum, item) => sum + item.content.length, 0);
      const claim = await deps.repository.claimRequest({
        userId,
        requestId: validated.requestId!,
        config: snapshot.config,
        model: selectedModel,
        inputChars,
        historyMessages: messages.length,
        now: deps.now(),
      });
      if (claim.status === "daily_limit_reached") {
        throw new AiChatError("daily_limit_reached", claim.retryAfterSeconds ?? null);
      }
      if (claim.status === "burst_limit_reached") {
        throw new AiChatError("rate_limited", claim.retryAfterSeconds ?? null);
      }
      if (claim.status !== "claimed") throw new AiChatError("duplicate_request");

      const access = await deps.repository.claimProviderAccess(
        snapshot.config.providerKind,
        deps.now(),
        Math.max(1, Math.ceil(snapshot.config.providerTimeoutMs / 1000) + 5),
      );
      if (!access.allowed) {
        const failure = new AiChatError("provider_unavailable", access.retryAfterSeconds ?? null);
        await deps.repository.completeRequest({
          userId,
          requestId: validated.requestId!,
          status: "failed",
          model: selectedModel,
          latencyMs: Math.max(0, deps.now().getTime() - startedAt.getTime()),
          outputChars: null,
          promptTokens: null,
          completionTokens: null,
          errorCode: failure.code,
          completedAt: deps.now(),
        });
        throw failure;
      }

      const endpoint = new URL(snapshot.config.providerApiPath, snapshot.config.providerBaseUrl);
      let lastError: AiChatError | null = null;
      let result: Awaited<ReturnType<AiChatProvider["complete"]>> | null = null;
      let usedModel = selectedModel;
      let totalAttempts = 0;

      modelLoop:
      for (const model of models) {
        const attemptsForModel = 1 + snapshot.config.transportRetryCount;
        for (let attempt = 0; attempt < attemptsForModel; attempt += 1) {
          totalAttempts += 1;
          usedModel = model;
          try {
            result = await deps.provider.complete({
              model,
              instructions: snapshot.prompt.instructions,
              messages,
              maxOutputTokens: snapshot.config.maxOutputTokens,
              timeoutMs: Math.min(
                snapshot.config.providerTimeoutMs,
                HARD_MAX_PROVIDER_TIMEOUT_MS,
              ),
              gatewaySecret: credentials.gatewaySecret,
              apiKey: credentials.apiKey,
              endpoint,
            });
            lastError = null;
            break modelLoop;
          } catch (error) {
            lastError = providerError(error);
            if (!canRetryTransport(lastError)) break modelLoop;
            if (attempt + 1 < attemptsForModel) continue;
          }
        }
      }

      const latencyMs = Math.max(0, deps.now().getTime() - startedAt.getTime());
      if (result === null) {
        const failure = lastError ?? new AiChatError("provider_unavailable");
        await deps.repository.completeRequest({
          userId,
          requestId: validated.requestId!,
          status: "failed",
          model: usedModel,
          latencyMs,
          outputChars: null,
          promptTokens: null,
          completionTokens: null,
          errorCode: failure.code,
          completedAt: deps.now(),
        });
        await deps.repository.recordProviderResult({
          config: snapshot.config,
          success: false,
          retryableFailure: canRetryTransport(failure) || failure.code === "provider_timeout",
          errorCode: failure.code,
          latencyMs,
          now: deps.now(),
        });
        throw failure;
      }

      await deps.repository.completeRequest({
        userId,
        requestId: validated.requestId!,
        status: "completed",
        model: usedModel,
        latencyMs,
        outputChars: result.text.length,
        promptTokens: result.promptTokens ?? null,
        completionTokens: result.completionTokens ?? null,
        errorCode: null,
        completedAt: deps.now(),
      });
      await deps.repository.recordProviderResult({
        config: snapshot.config,
        success: true,
        retryableFailure: false,
        errorCode: null,
        latencyMs,
        now: deps.now(),
      });
      deps.logger.info({
        operation,
        requestId,
        contractVersion: 1,
        configVersion: snapshot.config.configVersion,
        outcome: "success",
        status: 200,
        latencyMs,
        retryCount: Math.max(0, totalAttempts - 1),
        inputChars,
        historyMessages: messages.length,
        outputChars: result.text.length,
        locale: validated.client.locale,
      });
      return jsonResponse({
        contractVersion: 1,
        requestId: validated.requestId,
        configVersion: snapshot.config.configVersion,
        serverTime: deps.now().toISOString(),
        message: { role: "assistant", content: result.text },
        quota: {
          dailyRemaining: claim.dailyRemaining ?? 0,
          burstRemaining: claim.burstRemaining ?? 0,
          resetsAt: claim.dailyResetsAt,
        },
      });
    } catch (error) {
      const safe = error instanceof AiChatError ? error : new AiChatError("internal_error");
      deps.logger.error({
        operation,
        requestId,
        contractVersion: 1,
        outcome: safe.code,
        status: safe.status,
        latencyMs: Math.max(0, deps.now().getTime() - startedAt.getTime()),
      });
      return errorResponse(safe, requestId, deps.now(), {
        "X-Content-Type-Options": "nosniff",
      });
    }
  };
}
