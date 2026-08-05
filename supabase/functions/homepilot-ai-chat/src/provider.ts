import type { ProviderChatRequest, ProviderChatResult } from "./contracts.ts";

export interface AiChatProvider {
  complete(request: ProviderChatRequest): Promise<ProviderChatResult>;
}
