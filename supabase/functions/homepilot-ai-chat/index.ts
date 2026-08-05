import { createSupabaseContext } from "@supabase/server";
import { CliProxyApiProvider } from "./src/cliproxyapi_provider.ts";
import { AiChatError, errorResponse } from "./src/errors.ts";
import { createHandler } from "./src/handler.ts";
import { consoleSafeLogger } from "./src/logging.ts";
import { SupabaseGatewayRepository } from "./src/repositories.ts";

function required(name: string): string {
  const value = Deno.env.get(name)?.trim();
  if (!value) throw new AiChatError("server_configuration_error");
  return value;
}

Deno.serve(async (request: Request): Promise<Response> => {
  const now = new Date();
  try {
    const { data: context, error } = await createSupabaseContext(request, {
      auth: "user",
    });
    const userId = context?.userClaims?.id;
    if (error || typeof userId !== "string" || userId.length === 0) {
      return errorResponse(new AiChatError("session_invalid"), null, now);
    }
    return createHandler({
      authenticatedUserId: userId,
      repository: new SupabaseGatewayRepository(context.supabaseAdmin),
      provider: new CliProxyApiProvider(),
      providerCredentials: () => ({
        apiKey: required("AI_PROVIDER_API_KEY"),
        gatewaySecret: required("AI_GATEWAY_SHARED_SECRET"),
      }),
      logger: consoleSafeLogger,
      now: () => new Date(),
    })(request);
  } catch {
    return errorResponse(
      new AiChatError("server_configuration_error"),
      null,
      now,
    );
  }
});
