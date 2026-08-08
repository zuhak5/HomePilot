import assert from 'node:assert/strict';
import test from 'node:test';

import {
  accessTokenFromLocation,
  buildGoogleAuthorizeUrl,
  fetchAuthenticatedUser,
  requestAccountDeletion,
  validatePublicConfig,
} from '../download-site/account-deletion.js';
import {
  renderDeletionConfig,
  validateDeletionConfig,
} from './build_account_deletion_config.mjs';

const config = {
  supabaseUrl: 'https://example.supabase.co',
  anonKey: 'public-anon-key',
  redirectUrl: 'https://example.com/account-deletion.html',
};

test('public config rejects service-role and insecure values', () => {
  assert.throws(() => validatePublicConfig({ ...config, supabaseUrl: 'http://example.test' }));
  assert.throws(() => validatePublicConfig({ ...config, anonKey: 'service_role_secret' }));
  assert.throws(() => validateDeletionConfig({
    HOMEPILOT_SUPABASE_URL: config.supabaseUrl,
    HOMEPILOT_SUPABASE_ANON_KEY: 'service-role-secret',
    HOMEPILOT_ACCOUNT_DELETION_REDIRECT_URL: config.redirectUrl,
  }));
});

test('Google authorization URL targets Supabase and exact deletion redirect', () => {
  const url = new URL(buildGoogleAuthorizeUrl(config));
  assert.equal(url.origin, 'https://example.supabase.co');
  assert.equal(url.pathname, '/auth/v1/authorize');
  assert.equal(url.searchParams.get('provider'), 'google');
  assert.equal(url.searchParams.get('redirect_to'), config.redirectUrl);
});

test('OAuth access token is read only from bearer fragment', () => {
  assert.equal(accessTokenFromLocation({ hash: '#access_token=token-1&token_type=bearer' }), 'token-1');
  assert.equal(accessTokenFromLocation({ hash: '#access_token=token-1&token_type=mac' }), null);
  assert.equal(accessTokenFromLocation({ hash: '' }), null);
});

test('identity verification sends public key and bearer token', async () => {
  let request;
  const user = await fetchAuthenticatedUser({
    config,
    accessToken: 'access-token',
    fetchImpl: async (url, init) => {
      request = { url, init };
      return new Response(JSON.stringify({ id: 'user-1', email: 'user@example.com' }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    },
  });
  assert.equal(user.id, 'user-1');
  assert.equal(request.url, 'https://example.supabase.co/auth/v1/user');
  assert.equal(request.init.headers.apikey, config.anonKey);
  assert.equal(request.init.headers.Authorization, 'Bearer access-token');
});

test('deletion requires backend-confirmed deleted receipt', async () => {
  let request;
  const result = await requestAccountDeletion({
    config,
    accessToken: 'access-token',
    fetchImpl: async (url, init) => {
      request = { url, init };
      return new Response(JSON.stringify({ deleted: true, status: 'deleted' }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      });
    },
  });
  assert.equal(result.deleted, true);
  assert.equal(request.url, 'https://example.supabase.co/functions/v1/delete-account');
  assert.deepEqual(JSON.parse(request.init.body), { confirmation: 'delete-my-account' });
  assert.equal(request.init.headers.Authorization, 'Bearer access-token');
});

test('deletion never accepts cosmetic 200 without deletion receipt', async () => {
  await assert.rejects(
    requestAccountDeletion({
      config,
      accessToken: 'access-token',
      fetchImpl: async () => new Response(JSON.stringify({ status: 'ok' }), {
        status: 200,
        headers: { 'content-type': 'application/json' },
      }),
    }),
    /deletion_not_confirmed/,
  );
});

test('generated browser config contains no service-role field', () => {
  const rendered = renderDeletionConfig(config);
  assert.match(rendered, /HOME_PILOT_ACCOUNT_DELETION_CONFIG/);
  assert.doesNotMatch(rendered, /service[_-]?role/i);
});
