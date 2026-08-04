# Monetization Architecture

## Scope

HomePilot integrates Google Mobile Ads with a server-authoritative points system. The monetization design must preserve user consent, core-data integrity, reward replay protection, and predictable offline behavior.

## Components

- Flutter ad initialization and consent handling.
- Native, interstitial, rewarded, and rewarded-interstitial presentation where enabled.
- Local monetization configuration and cooldown state.
- Supabase wallet and ledger records.
- Point-debited creation RPCs.
- Pending reward claims.
- The `admob-ssv-handler` Edge Function.
- Ad and reward diagnostics that exclude credentials and user content.

## Authority model

The backend is authoritative for:

- Current point balance.
- Debit and credit ledger entries.
- Whether a charged creation succeeds.
- Whether a reward claim is valid and unused.
- SSV signature and request validation.
- Replay prevention and idempotency.

Flutter may display cached state and initiate operations, but it must not directly alter authoritative wallet values.

## Consent and initialization

Ad initialization should:

1. Resolve consent requirements for the current environment.
2. Request consent only through approved user-facing flows.
3. Handle unavailable, denied, or failed consent without corrupting core application state.
4. Use test identifiers outside production.
5. Avoid sending HomePilot domain data in ad request metadata.

Core asset and maintenance features should remain coherent when ads are unavailable.

## Point-debited creation

A point-gated operation should use a single backend transaction or RPC that:

1. Authenticates the user.
2. Validates the request and current configuration.
3. Checks available balance.
4. Applies an idempotency key.
5. Debits the wallet and creates the target record atomically, or performs neither.
6. Returns the authoritative result and balance.

The client must not debit locally and then separately create cloud data.

## Offline behavior

When a charged operation cannot be confirmed by the server:

- Do not present it as completed.
- Preserve user-entered work only as an explicit unfinished local draft when supported.
- Do not enqueue a blind wallet mutation that can double-charge later.
- Resume through a reviewed idempotent workflow after connectivity returns.

## Rewarded ads

A device-side reward callback indicates that an ad SDK flow reached a reward point; it is not sufficient authority to credit points.

The client should create or retain an opaque pending claim. The server-side verification handler then validates the SSV request, associates it with the intended account and claim, rejects replay, and credits points idempotently.

## SSV security

The verification function must:

- Validate required request fields and signature material according to current Google documentation.
- Avoid trusting a client-supplied user identity without a protected binding mechanism.
- Use opaque claim identifiers rather than user content.
- Enforce expiry, replay protection, and one-time credit.
- Make duplicate valid callbacks return an idempotent result.
- Avoid logging signatures, secrets, full provider payloads, or direct identifiers.

## Failure states

Handle explicitly:

- Consent unavailable or denied.
- Ad load failure.
- Ad closed without reward.
- Reward callback without later SSV.
- SSV before client refresh.
- Duplicate or delayed SSV.
- Invalid signature.
- Unknown or expired claim.
- Insufficient points.
- RPC timeout after possible commit.
- Configuration disabled.
- Account sign-out or deletion with pending claims.

## Testing

Use provider test modes and local Supabase tests. Cover wallet conservation, atomic debit/create, duplicate idempotency keys, replayed SSV, invalid signatures, wrong account, expiry, offline drafts, timeout/retry, and consent-disabled operation.

## Privacy

Advertising and reward changes require review of consent, identifiers, third-party processing, retention, logging, deletion, and `PRIVACY.md`. Do not place room names, asset names, maintenance content, location, email, or media references in ad or reward metadata.