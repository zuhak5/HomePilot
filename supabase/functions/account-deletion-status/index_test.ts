import { assertEquals, assertMatch } from "jsr:@std/assert@1.0.16";

import {
  type AccountDeletionStatusServices,
  handleAccountDeletionStatus,
  type StatusServiceFactory,
} from "./index.ts";

const userId = "11111111-1111-4111-8111-111111111111";
const recoveryKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA";
const productionOrigin = "https://zuhak5.github.io";
const configuredEnvironment = {
  get: (key: string): string | undefined =>
    ({
      SUPABASE_URL: "https://example.supabase.co",
      SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",
    })[key],
};
const emptyEnvironment = { get: (_key: string): undefined => undefined };

Deno.test("status endpoint is non-destructive POST only", async () => {
  const response = await handleAccountDeletionStatus(
    new Request("http://localhost/account-deletion-status"),
    emptyEnvironment,
  );
  assertEquals(response.status, 405);
  assertEquals(await response.json(), { error: "method_not_allowed" });
  assertEquals(response.headers.get("cache-control"), "no-store");
});

Deno.test("status endpoint has exact CORS allowlist", async () => {
  const allowed = await handleAccountDeletionStatus(
    new Request("http://localhost/account-deletion-status", {
      method: "OPTIONS",
      headers: { Origin: productionOrigin },
    }),
    emptyEnvironment,
  );
  assertEquals(allowed.status, 204);
  assertEquals(
    allowed.headers.get("access-control-allow-origin"),
    productionOrigin,
  );
  assertEquals(
    allowed.headers.get("access-control-allow-headers"),
    "apikey, content-type, x-client-info",
  );

  const denied = await handleAccountDeletionStatus(
    recoveryRequest({ origin: "https://attacker.example" }),
    emptyEnvironment,
  );
  assertEquals(denied.status, 403);
  assertEquals(await denied.json(), { error: "origin_not_allowed" });
});

Deno.test("status endpoint rejects malformed capabilities and identifiers", async () => {
  for (
    const body of [
      {},
      { recovery_key: "short", expected_user_id: userId },
      { recovery_key: recoveryKey, expected_user_id: "not-a-uuid" },
    ]
  ) {
    const response = await handleAccountDeletionStatus(
      recoveryRequest({ body }),
      emptyEnvironment,
    );
    assertEquals(response.status, 400);
    assertEquals(await response.json(), { error: "invalid_recovery_request" });
  }
});

Deno.test("unknown or mismatched capability reveals no operation", async () => {
  const services = new FakeStatusServices();
  services.operation = null;
  const response = await handleAccountDeletionStatus(
    recoveryRequest(),
    configuredEnvironment,
    factoryFor(services),
  );
  assertEquals(response.status, 404);
  assertEquals(await response.json(), { error: "recovery_not_found" });
  assertEquals(services.events.length, 1);
  assertMatch(services.events[0], /^lookup:[0-9a-f]{64}:[0-9a-f]{64}$/);
});

Deno.test("completed capability returns strict same-user receipt", async () => {
  const services = new FakeStatusServices();
  services.operation = {
    operationId: "33333333-3333-4333-8333-333333333333",
    stage: "completed",
    activeUserId: null,
    completed: true,
  };
  const response = await handleAccountDeletionStatus(
    recoveryRequest({ origin: productionOrigin }),
    configuredEnvironment,
    factoryFor(services),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    deleted: true,
    status: "deleted",
    user_id: userId,
  });
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    productionOrigin,
  );
  assertEquals(
    services.events.some((event) => event.startsWith("exists:")),
    false,
  );
});

Deno.test("pre-delete operation remains pending without Auth lookup", async () => {
  const services = new FakeStatusServices();
  services.operation = {
    operationId: "33333333-3333-4333-8333-333333333333",
    stage: "storage_complete",
    activeUserId: userId,
    completed: false,
  };
  const response = await handleAccountDeletionStatus(
    recoveryRequest(),
    configuredEnvironment,
    factoryFor(services),
  );
  assertEquals(response.status, 202);
  assertEquals(await response.json(), { deleted: false, status: "pending" });
  assertEquals(
    services.events.some((event) => event.startsWith("exists:")),
    false,
  );
});

Deno.test("Auth deletion boundary stays pending while Auth user exists", async () => {
  const services = authDeleteStartedServices();
  services.userExists = true;
  const response = await handleAccountDeletionStatus(
    recoveryRequest(),
    configuredEnvironment,
    factoryFor(services),
  );
  assertEquals(response.status, 202);
  assertEquals(await response.json(), { deleted: false, status: "pending" });
  assertEquals(services.events.includes(`complete:${userId}`), false);
});

Deno.test("lost response is finalized only after Auth user is absent", async () => {
  const services = authDeleteStartedServices();
  services.userExists = false;
  const response = await handleAccountDeletionStatus(
    recoveryRequest(),
    configuredEnvironment,
    factoryFor(services),
  );
  assertEquals(response.status, 200);
  assertEquals(await response.json(), {
    deleted: true,
    status: "deleted",
    user_id: userId,
  });
  assertEquals(services.events.includes(`complete:${userId}`), true);
});

class FakeStatusServices implements AccountDeletionStatusServices {
  events: string[] = [];
  operation: Awaited<
    ReturnType<AccountDeletionStatusServices["lookupOperation"]>
  > = null;
  userExists = true;

  lookupOperation(
    requestHash: string,
    subjectBinding: string,
  ): Promise<typeof this.operation> {
    this.events.push(`lookup:${requestHash}:${subjectBinding}`);
    return Promise.resolve(this.operation);
  }

  authUserExists(user: string): Promise<boolean> {
    this.events.push(`exists:${user}`);
    return Promise.resolve(this.userExists);
  }

  completeOperation(
    _operationId: string,
    user: string,
    _subjectBinding: string,
  ): Promise<void> {
    this.events.push(`complete:${user}`);
    return Promise.resolve();
  }
}

function authDeleteStartedServices(): FakeStatusServices {
  const services = new FakeStatusServices();
  services.operation = {
    operationId: "33333333-3333-4333-8333-333333333333",
    stage: "auth_delete_started",
    activeUserId: userId,
    completed: false,
  };
  return services;
}

function factoryFor(
  services: AccountDeletionStatusServices,
): StatusServiceFactory {
  return () => services;
}

function recoveryRequest({
  body = { recovery_key: recoveryKey, expected_user_id: userId },
  origin,
}: {
  body?: Record<string, unknown>;
  origin?: string;
} = {}): Request {
  const headers = new Headers({ "Content-Type": "application/json" });
  if (origin != null) headers.set("Origin", origin);
  return new Request("http://localhost/account-deletion-status", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}
