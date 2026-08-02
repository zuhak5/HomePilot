import { assertEquals, assertMatch } from "jsr:@std/assert@1.0.16";

import {
  type AccountDeletionServices,
  handleDeleteAccount,
  type ServiceFactory,
} from "./index.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const sessionId = "22222222-2222-4222-8222-222222222222";
const validToken = jwtWithSession(sessionId);
const configuredEnvironment = {
  get: (key: string): string | undefined =>
    ({
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_ANON_KEY: "anon-test-key",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",
    })[key],
};
const emptyEnvironment = {
  get: (_key: string): undefined => undefined,
};

Deno.test("rejects non-POST methods before reading credentials", async () => {
  const response = await handleDeleteAccount(
    new Request("http://localhost/delete-account"),
    emptyEnvironment,
  );

  assertEquals(response.status, 405);
  assertEquals(await response.json(), { error: "method_not_allowed" });
  assertMatch(response.headers.get("content-type") ?? "", /application\/json/);
  assertEquals(response.headers.get("cache-control"), "no-store");
});

Deno.test("requires a bearer authorization header", async () => {
  const response = await handleDeleteAccount(
    deletionRequest({ includeAuthorization: false }),
    emptyEnvironment,
  );

  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "missing_authorization" });
});

Deno.test("requires an explicit deletion confirmation payload", async () => {
  const response = await handleDeleteAccount(
    deletionRequest({ confirmation: "not-confirmed" }),
    emptyEnvironment,
  );

  assertEquals(response.status, 400);
  assertEquals(await response.json(), { error: "confirmation_required" });
});

Deno.test("fails closed when server credentials are unavailable", async () => {
  const response = await handleDeleteAccount(
    deletionRequest(),
    emptyEnvironment,
  );

  assertEquals(response.status, 500);
  assertEquals(await response.json(), { error: "server_configuration_error" });
});

Deno.test("rejects a token without a valid session id", async () => {
  const response = await handleDeleteAccount(
    deletionRequest({ token: "not-a-jwt" }),
    configuredEnvironment,
  );

  assertEquals(response.status, 401);
  assertEquals(await response.json(), { error: "invalid_session" });
});

Deno.test("requires a recent reauthenticated session", async () => {
  const services = new FakeAccountDeletionServices();
  services.recentSession = false;

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 403);
  assertEquals(await response.json(), {
    error: "recent_reauthentication_required",
  });
  assertEquals(services.events, [
    "get_user",
    `recent_session:${userId}:${sessionId}`,
  ]);
});

Deno.test("deletes only the user derived from the verified JWT", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push(
    [`${userId}/assets/photo.jpg`],
    [`${userId}/assets/photo.jpg`],
    [],
  );

  const response = await handleDeleteAccount(
    deletionRequest({
      extraBody: {
        user_id: "99999999-9999-4999-8999-999999999999",
      },
    }),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 200);
  assertEquals(await response.json(), { deleted: true });
  assertEquals(services.events, [
    "get_user",
    `recent_session:${userId}:${sessionId}`,
    `list:${userId}`,
    `begin:${userId}:1`,
    "sign_out_global",
    `list:${userId}`,
    "remove:1",
    `list:${userId}`,
    `delete_user:${userId}`,
  ]);
});

Deno.test("does not delete Auth when Storage cleanup fails", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push(
    [`${userId}/assets/photo.jpg`],
    [`${userId}/assets/photo.jpg`],
  );
  services.removeError = new Error("forced storage failure");

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "storage_cleanup_failed" });
  assertEquals(
    services.events.some((event) => event.startsWith("delete_user:")),
    false,
  );
  assertEquals(
    services.events.includes("record_error:remove_storage_failed"),
    true,
  );
});

Deno.test("does not start cleanup when global sign-out fails", async () => {
  const services = new FakeAccountDeletionServices();
  services.objectListings.push([]);
  services.signOutError = new Error("forced sign-out failure");

  const response = await handleDeleteAccount(
    deletionRequest(),
    configuredEnvironment,
    factoryFor(services),
  );

  assertEquals(response.status, 503);
  assertEquals(await response.json(), { error: "session_revocation_failed" });
  assertEquals(
    services.events.includes("record_error:revoke_sessions_failed"),
    true,
  );
  assertEquals(
    services.events.some((event) => event.startsWith("delete_user:")),
    false,
  );
});

class FakeAccountDeletionServices implements AccountDeletionServices {
  events: string[] = [];
  objectListings: string[][] = [];
  recentSession = true;
  signOutError: unknown = null;
  removeError: unknown = null;

  getVerifiedUserId(_token: string): Promise<string | null> {
    this.events.push("get_user");
    return Promise.resolve(userId);
  }

  isRecentSession(user: string, session: string): Promise<boolean> {
    this.events.push(`recent_session:${user}:${session}`);
    return Promise.resolve(this.recentSession);
  }

  signOutGlobally(_token: string): Promise<void> {
    this.events.push("sign_out_global");
    return this.signOutError == null
      ? Promise.resolve()
      : Promise.reject(this.signOutError);
  }

  listObjectPaths(user: string): Promise<string[]> {
    this.events.push(`list:${user}`);
    return Promise.resolve(this.objectListings.shift() ?? []);
  }

  beginCleanup(user: string, objectPaths: string[]): Promise<string> {
    this.events.push(`begin:${user}:${objectPaths.length}`);
    return Promise.resolve("33333333-3333-4333-8333-333333333333");
  }

  removeObjects(objectPaths: string[]): Promise<void> {
    this.events.push(`remove:${objectPaths.length}`);
    return this.removeError == null
      ? Promise.resolve()
      : Promise.reject(this.removeError);
  }

  deleteUser(user: string): Promise<void> {
    this.events.push(`delete_user:${user}`);
    return Promise.resolve();
  }

  recordCleanupError(_jobId: string, errorCode: string): Promise<void> {
    this.events.push(`record_error:${errorCode}`);
    return Promise.resolve();
  }
}

function factoryFor(services: AccountDeletionServices): ServiceFactory {
  return () => services;
}

function deletionRequest({
  includeAuthorization = true,
  confirmation = "delete-my-account",
  token = validToken,
  extraBody = {},
}: {
  includeAuthorization?: boolean;
  confirmation?: string;
  token?: string;
  extraBody?: Record<string, unknown>;
} = {}): Request {
  return new Request("http://localhost/delete-account", {
    method: "POST",
    headers: includeAuthorization ? { Authorization: `Bearer ${token}` } : {},
    body: JSON.stringify({ confirmation, ...extraBody }),
  });
}

function jwtWithSession(session: string): string {
  const encode = (value: Record<string, string>): string =>
    btoa(JSON.stringify(value)).replaceAll("+", "-").replaceAll("/", "_")
      .replaceAll("=", "");
  return `${encode({ alg: "none" })}.${encode({ session_id: session })}.sig`;
}
