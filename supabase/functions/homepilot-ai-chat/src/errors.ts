export type ErrorCode =
  | "method_not_allowed"
  | "unsupported_media_type"
  | "request_too_large"
  | "invalid_json"
  | "invalid_request"
  | "unsupported_contract"
  | "authentication_required"
  | "session_invalid"
  | "feature_hidden"
  | "feature_disabled"
  | "maintenance"
  | "rollout_unavailable"
  | "unsupported_app_version"
  | "disclosure_required"
  | "input_too_long"
  | "history_too_large"
  | "daily_limit_reached"
  | "rate_limited"
  | "duplicate_request"
  | "provider_timeout"
  | "provider_unavailable"
  | "provider_auth_failed"
  | "invalid_provider_response"
  | "server_configuration_error"
  | "internal_error";

const STATUS: Record<ErrorCode, number> = {
  method_not_allowed: 405,
  unsupported_media_type: 415,
  request_too_large: 413,
  invalid_json: 400,
  invalid_request: 400,
  unsupported_contract: 400,
  authentication_required: 401,
  session_invalid: 401,
  feature_hidden: 404,
  feature_disabled: 503,
  maintenance: 503,
  rollout_unavailable: 403,
  unsupported_app_version: 426,
  disclosure_required: 409,
  input_too_long: 400,
  history_too_large: 400,
  daily_limit_reached: 429,
  rate_limited: 429,
  duplicate_request: 409,
  provider_timeout: 504,
  provider_unavailable: 503,
  provider_auth_failed: 503,
  invalid_provider_response: 502,
  server_configuration_error: 503,
  internal_error: 500,
};

const RETRYABLE = new Set<ErrorCode>([
  "maintenance",
  "rate_limited",
  "provider_timeout",
  "provider_unavailable",
  "invalid_provider_response",
  "internal_error",
]);

export class AiChatError extends Error {
  constructor(
    public readonly code: ErrorCode,
    public readonly retryAfterSeconds: number | null = null,
  ) {
    super(code);
  }

  get status(): number {
    return STATUS[this.code];
  }

  get retryable(): boolean {
    return RETRYABLE.has(this.code);
  }
}

export function errorResponse(
  error: AiChatError,
  requestId: string | null,
  now: Date,
  extraHeaders: HeadersInit = {},
): Response {
  const headers = new Headers(extraHeaders);
  headers.set("Content-Type", "application/json; charset=utf-8");
  headers.set("Cache-Control", "no-store");
  if (error.retryAfterSeconds !== null) {
    headers.set("Retry-After", String(error.retryAfterSeconds));
  }
  return new Response(JSON.stringify({
    contractVersion: 1,
    error: {
      code: error.code,
      retryable: error.retryable,
      retryAfterSeconds: error.retryAfterSeconds,
    },
    requestId,
    serverTime: now.toISOString(),
  }), { status: error.status, headers });
}
