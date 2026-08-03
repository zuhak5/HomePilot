import { createClient, type SupabaseClient } from "@supabase/supabase-js";

const jsonHeaders = {
  "Content-Type": "application/json",
  "Cache-Control": "no-store",
};
const requiredConfirmation = "delete-my-account";

type EnvironmentReader = Pick<typeof Deno.env, "get">;

export interface AccountDeletionServices {
  getVerifiedUserId(token: string): Promise<string | null>;
  isRecentSession(userId: string, sessionId: string): Promise<boolean>;
  signOutGlobally(token: string): Promise<void>;
  listObjectPaths(userId: string): Promise<string[]>;
  beginCleanup(userId: string, objectPaths: string[]): Promise<string>;
  removeObjects(objectPaths: string[]): Promise<void>;
  deleteUser(userId: string): Promise<void>;
  completeCleanup(jobId: string): Promise<void>;
  recordCleanupError(jobId: string, errorCode: string): Promise<void>;
}

export type ServiceFactory = (
  supabaseUrl: string,
  anonKey: string,
  serviceRoleKey: string,
  authorization: string,
) => AccountDeletionServices;

export async function handleDeleteAccount(
  request: Request,
  environment: EnvironmentReader = Deno.env,
  createServices: ServiceFactory = createAccountDeletionServices,
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  const authorization = request.headers.get("Authorization");
  if (!authorization?.startsWith("Bearer ")) {
    return jsonResponse(401, { error: "missing_authorization" });
  }

  if (!await hasDeletionConfirmation(request)) {
    return jsonResponse(400, { error: "confirmation_required" });
  }

  const supabaseUrl = environment.get("SUPABASE_URL");
  const anonKey = environment.get("SUPABASE_ANON_KEY");
  const serviceRoleKey = environment.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !anonKey || !serviceRoleKey) {
    return jsonResponse(500, { error: "server_configuration_error" });
  }

  const token = authorization.slice("Bearer ".length);
  const sessionId = sessionIdFromJwt(token);
  if (sessionId == null) {
    return jsonResponse(401, { error: "invalid_session" });
  }

  const services = createServices(
    supabaseUrl,
    anonKey,
    serviceRoleKey,
    authorization,
  );
  const userId = await services.getVerifiedUserId(token);
  if (userId == null) {
    return jsonResponse(401, { error: "invalid_session" });
  }

  if (!await services.isRecentSession(userId, sessionId)) {
    return jsonResponse(403, { error: "recent_reauthentication_required" });
  }

  let cleanupJobId: string | null = null;
  let phase = "prepare_cleanup";
  try {
    const initialObjectPaths = await services.listObjectPaths(userId);
    cleanupJobId = await services.beginCleanup(userId, initialObjectPaths);

    phase = "remove_storage";
    await removeAllUserObjects(services, userId);

    phase = "revoke_sessions";
    await services.signOutGlobally(token);

    phase = "delete_auth_user";
    await services.deleteUser(userId);

    phase = "complete_cleanup";
    await services.completeCleanup(cleanupJobId);

    return jsonResponse(200, {
      deleted: true,
      status: "deleted",
      user_id: userId,
    });
  } catch (error) {
    const errorCode = `${phase}_failed`;
    if (cleanupJobId != null) {
      try {
        await services.recordCleanupError(cleanupJobId, errorCode);
      } catch (recordError) {
        logDeletionFailure("record_cleanup_error", recordError);
      }
    }
    logDeletionFailure(phase, error);
    switch (phase) {
      case "revoke_sessions":
        return jsonResponse(503, { error: "session_revocation_failed" });
      case "remove_storage":
        return jsonResponse(503, { error: "storage_cleanup_failed" });
      case "delete_auth_user":
      case "complete_cleanup":
        return jsonResponse(500, { error: "account_deletion_failed" });
      default:
        return jsonResponse(500, { error: "account_deletion_failed" });
    }
  }
}

if (import.meta.main) {
  Deno.serve((request) => handleDeleteAccount(request));
}

function createAccountDeletionServices(
  supabaseUrl: string,
  anonKey: string,
  serviceRoleKey: string,
  authorization: string,
): AccountDeletionServices {
  const userClient = createClient(supabaseUrl, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  });

  return {
    async getVerifiedUserId(token: string): Promise<string | null> {
      const { data, error } = await userClient.auth.getUser(token);
      return error == null ? data.user?.id ?? null : null;
    },
    async isRecentSession(userId: string, sessionId: string): Promise<boolean> {
      const { data, error } = await admin.rpc("is_recent_homepilot_session", {
        p_user_id: userId,
        p_session_id: sessionId,
      });
      if (error) throw error;
      return data === true;
    },
    async signOutGlobally(token: string): Promise<void> {
      const { error } = await admin.auth.admin.signOut(token, "global");
      if (error) throw error;
    },
    listObjectPaths: (userId: string) =>
      listObjectPaths(admin, "user-media", userId),
    async beginCleanup(
      userId: string,
      objectPaths: string[],
    ): Promise<string> {
      const { data, error } = await admin.rpc(
        "begin_homepilot_account_cleanup",
        { p_user_id: userId, p_object_paths: objectPaths },
      );
      if (error || typeof data !== "string") {
        throw error ?? new Error("cleanup_job_creation_failed");
      }
      return data;
    },
    removeObjects: (objectPaths: string[]) =>
      removeObjectsWithRetry(admin, "user-media", objectPaths),
    async deleteUser(userId: string): Promise<void> {
      const { error } = await admin.auth.admin.deleteUser(userId);
      if (error) throw error;
    },
    async completeCleanup(jobId: string): Promise<void> {
      const { error } = await admin.rpc("complete_homepilot_account_cleanup", {
        p_job_id: jobId,
        p_error: null,
      });
      if (error) throw error;
    },
    async recordCleanupError(jobId: string, errorCode: string): Promise<void> {
      await admin.rpc("complete_homepilot_account_cleanup", {
        p_job_id: jobId,
        p_error: errorCode,
      });
    },
  };
}

async function hasDeletionConfirmation(request: Request): Promise<boolean> {
  try {
    const body: unknown = await request.json();
    return typeof body === "object" && body != null &&
      "confirmation" in body &&
      body.confirmation === requiredConfirmation;
  } catch {
    return false;
  }
}

function sessionIdFromJwt(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const encoded = parts[1].replaceAll("-", "+").replaceAll("_", "/");
    const padded = encoded.padEnd(Math.ceil(encoded.length / 4) * 4, "=");
    const binary = atob(padded);
    const bytes = Uint8Array.from(binary, (value) => value.charCodeAt(0));
    const payload: unknown = JSON.parse(new TextDecoder().decode(bytes));
    if (
      typeof payload !== "object" || payload == null ||
      !("session_id" in payload)
    ) {
      return null;
    }
    const sessionId = payload.session_id;
    return typeof sessionId === "string" && isUuid(sessionId)
      ? sessionId
      : null;
  } catch {
    return null;
  }
}

function isUuid(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    .test(value);
}

async function removeAllUserObjects(
  services: AccountDeletionServices,
  userId: string,
): Promise<void> {
  for (let pass = 0; pass < 3; pass++) {
    const objectPaths = await services.listObjectPaths(userId);
    if (objectPaths.length === 0) return;
    await services.removeObjects(objectPaths);
  }
  if ((await services.listObjectPaths(userId)).length !== 0) {
    throw new Error("storage_cleanup_incomplete");
  }
}

async function listObjectPaths(
  admin: SupabaseClient,
  bucket: string,
  prefix: string,
): Promise<string[]> {
  const paths: string[] = [];
  let offset = 0;
  while (true) {
    const { data, error } = await admin.storage.from(bucket).list(prefix, {
      limit: 100,
      offset,
      sortBy: { column: "name", order: "asc" },
    });
    if (error) throw error;
    for (const item of data ?? []) {
      const path = `${prefix}/${item.name}`;
      if (item.id) {
        paths.push(path);
      } else {
        paths.push(...await listObjectPaths(admin, bucket, path));
      }
    }
    if (!data || data.length < 100) break;
    offset += data.length;
  }
  return paths;
}

async function removeObjectsWithRetry(
  admin: SupabaseClient,
  bucket: string,
  objectPaths: string[],
): Promise<void> {
  for (let index = 0; index < objectPaths.length; index += 100) {
    const batch = objectPaths.slice(index, index + 100);
    let lastError: Error | null = null;
    for (let attempt = 0; attempt < 3; attempt++) {
      const { error } = await admin.storage.from(bucket).remove(batch);
      if (!error) {
        lastError = null;
        break;
      }
      lastError = error;
      await new Promise((resolve) => setTimeout(resolve, 250 * 2 ** attempt));
    }
    if (lastError) throw lastError;
  }
}

function jsonResponse(
  status: number,
  body: Record<string, boolean | string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: jsonHeaders,
  });
}

function logDeletionFailure(phase: string, error: unknown): void {
  const errorName = error instanceof Error ? error.name : "UnknownError";
  console.error("account_deletion_failed", {
    phase,
    error_name: errorName.replaceAll(/[^A-Za-z0-9_.-]/g, "_"),
  });
}
