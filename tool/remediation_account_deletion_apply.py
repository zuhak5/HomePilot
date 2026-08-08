#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def apply() -> None:
    path = "supabase/functions/delete-account/index.ts"
    text = read(path)
    old_start = '''export async function handleDeleteAccount(
  request: Request,
  environment: EnvironmentReader = Deno.env,
  createServices: ServiceFactory = createAccountDeletionServices,
): Promise<Response> {
  if (request.method !== "POST") {
    return jsonResponse(405, { error: "method_not_allowed" });
  }

  const authorization = request.headers.get("Authorization");'''
    new_start = '''export async function handleDeleteAccount(
  request: Request,
  environment: EnvironmentReader = Deno.env,
  createServices: ServiceFactory = createAccountDeletionServices,
): Promise<Response> {
  const origin = request.headers.get("Origin");
  const corsHeaders = browserCorsHeaders(origin, environment);
  if (origin != null && corsHeaders == null) {
    return jsonResponse(403, { error: "origin_not_allowed" });
  }
  if (request.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        "Cache-Control": "no-store",
        ...(corsHeaders ?? {}),
      },
    });
  }
  const respond = (status: number, body: Record<string, boolean | string>) =>
    jsonResponse(status, body, corsHeaders ?? undefined);
  if (request.method !== "POST") {
    return respond(405, { error: "method_not_allowed" });
  }

  const authorization = request.headers.get("Authorization");'''
    if old_start not in text:
        raise RuntimeError("delete-account handler start changed")
    text = text.replace(old_start, new_start, 1)
    # Only inside the handler body before Deno.serve: all response helpers must
    # carry the validated browser Origin when present.
    handler, rest = text.split('\nif (import.meta.main)', 1)
    handler = handler.replace('return jsonResponse(', 'return respond(')
    # The success receipt deliberately avoids returning an account identifier.
    handler = handler.replace(
        '''    return respond(200, {
      deleted: true,
      status: "deleted",
      user_id: userId,
    });''',
        '''    return respond(200, {
      deleted: true,
      status: "deleted",
    });''',
    )
    text = handler + '\nif (import.meta.main)' + rest

    json_pattern = re.compile(
        r"function jsonResponse\(\n  status: number,\n  body: Record<string, boolean \| string>,\n\): Response \{\n  return new Response\(JSON\.stringify\(body\), \{\n    status,\n    headers: jsonHeaders,\n  \}\);\n\}",
        re.S,
    )
    json_replacement = '''function jsonResponse(
  status: number,
  body: Record<string, boolean | string>,
  extraHeaders?: Record<string, string>,
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...jsonHeaders, ...(extraHeaders ?? {}) },
  });
}

function browserCorsHeaders(
  origin: string | null,
  environment: EnvironmentReader,
): Record<string, string> | null {
  if (origin == null) return {};
  const allowed = (environment.get("ACCOUNT_DELETION_ALLOWED_ORIGINS") ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter((value) => value.length > 0);
  if (!allowed.includes(origin)) return null;
  return {
    "Access-Control-Allow-Origin": origin,
    "Access-Control-Allow-Headers": "authorization, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Vary": "Origin",
  };
}'''
    text, count = json_pattern.subn(json_replacement, text, count=1)
    if count != 1:
        raise RuntimeError(f"jsonResponse shape changed: {count}")
    write(path, text)

    test_path = "supabase/functions/delete-account/index_test.ts"
    tests = read(test_path)
    tests = tests.replace(
        '      SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",',
        '      SUPABASE_SERVICE_ROLE_KEY: "service-role-test-key",\n'
        '      ACCOUNT_DELETION_ALLOWED_ORIGINS: "https://homepilot.example",',
        1,
    )
    tests = tests.replace(
        '''  assertEquals(await response.json(), {
    deleted: true,
    status: "deleted",
    user_id: userId,
  });''',
        '''  assertEquals(await response.json(), {
    deleted: true,
    status: "deleted",
  });''',
        1,
    )
    insertion = r'''

Deno.test("allows configured browser preflight without reading credentials", async () => {
  const response = await handleDeleteAccount(
    new Request("http://localhost/delete-account", {
      method: "OPTIONS",
      headers: { Origin: "https://homepilot.example" },
    }),
    configuredEnvironment,
  );
  assertEquals(response.status, 204);
  assertEquals(
    response.headers.get("access-control-allow-origin"),
    "https://homepilot.example",
  );
});

Deno.test("rejects unconfigured browser origins before authorization", async () => {
  const response = await handleDeleteAccount(
    new Request("http://localhost/delete-account", {
      method: "POST",
      headers: { Origin: "https://evil.example" },
      body: JSON.stringify({ confirmation: "delete-my-account" }),
    }),
    configuredEnvironment,
  );
  assertEquals(response.status, 403);
  assertEquals(await response.json(), { error: "origin_not_allowed" });
  assertEquals(response.headers.get("access-control-allow-origin"), null);
});
'''
    anchor = '\nDeno.test("requires a bearer authorization header"'
    if anchor not in tests:
        raise RuntimeError("delete-account test anchor changed")
    tests = tests.replace(anchor, insertion + anchor, 1)
    write(test_path, tests)


if __name__ == "__main__":
    apply()
