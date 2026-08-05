import type { ProviderChatRequest, ProviderChatResult } from "./contracts.ts";
import { AiChatError } from "./errors.ts";
import type { AiChatProvider } from "./provider.ts";
import { parseProviderResponse } from "./response_parser.ts";

function providerInput(messages: ProviderChatRequest["messages"]): unknown[] {
  return messages.map((message) => ({
    role: message.role,
    content: message.content,
  }));
}

export class CliProxyApiProvider implements AiChatProvider {
  constructor(private readonly fetchImpl: typeof fetch = fetch) {}

  async complete(request: ProviderChatRequest): Promise<ProviderChatResult> {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), request.timeoutMs);
    try {
      let response: Response;
      try {
        response = await this.fetchImpl(request.endpoint, {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${request.apiKey}`,
            "Content-Type": "application/json",
            "Accept": "application/json",
            "X-HomePilot-Gateway-Secret": request.gatewaySecret,
          },
          body: JSON.stringify({
            model: request.model,
            instructions: request.instructions,
            input: providerInput(request.messages),
            max_output_tokens: request.maxOutputTokens,
          }),
          signal: controller.signal,
        });
      } catch (error) {
        if (error instanceof DOMException && error.name === "AbortError") {
          throw new AiChatError("provider_timeout");
        }
        throw new AiChatError("provider_unavailable");
      }
      if (response.status === 401 || response.status === 403) {
        throw new AiChatError("provider_auth_failed");
      }
      if (response.status === 429 || response.status === 502 || response.status === 503 || response.status === 504) {
        throw new AiChatError("provider_unavailable");
      }
      if (!response.ok) throw new AiChatError("invalid_provider_response");
      let payload: unknown;
      try {
        payload = await response.json();
      } catch {
        throw new AiChatError("invalid_provider_response");
      }
      return parseProviderResponse(payload);
    } finally {
      clearTimeout(timer);
    }
  }
}
