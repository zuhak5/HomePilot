const TOKEN_KEY = 'homepilot-account-deletion-access-token';

export function validatePublicConfig(config) {
  if (!config || typeof config !== 'object') throw new Error('missing_public_config');
  const supabaseUrl = String(config.supabaseUrl || '').replace(/\/$/, '');
  const anonKey = String(config.anonKey || '');
  const redirectUrl = String(config.redirectUrl || '');
  if (!/^https:\/\//.test(supabaseUrl)) throw new Error('invalid_supabase_url');
  if (!anonKey || anonKey.includes('service_role')) throw new Error('invalid_public_key');
  if (!/^https:\/\//.test(redirectUrl)) throw new Error('invalid_redirect_url');
  return { supabaseUrl, anonKey, redirectUrl };
}

export function buildGoogleAuthorizeUrl(config) {
  const safe = validatePublicConfig(config);
  const url = new URL(`${safe.supabaseUrl}/auth/v1/authorize`);
  url.searchParams.set('provider', 'google');
  url.searchParams.set('redirect_to', safe.redirectUrl);
  return url.toString();
}

export function accessTokenFromLocation(locationLike) {
  const hash = String(locationLike?.hash || '').replace(/^#/, '');
  if (!hash) return null;
  const params = new URLSearchParams(hash);
  const token = params.get('access_token');
  const type = params.get('token_type');
  return token && (!type || type.toLowerCase() === 'bearer') ? token : null;
}

export async function fetchAuthenticatedUser({ config, accessToken, fetchImpl = fetch }) {
  const safe = validatePublicConfig(config);
  const response = await fetchImpl(`${safe.supabaseUrl}/auth/v1/user`, {
    method: 'GET',
    headers: {
      apikey: safe.anonKey,
      Authorization: `Bearer ${accessToken}`,
      Accept: 'application/json',
    },
    cache: 'no-store',
    credentials: 'omit',
  });
  if (!response.ok) throw new Error('authentication_verification_failed');
  const body = await response.json();
  if (!body || typeof body.id !== 'string' || !body.id) {
    throw new Error('authentication_verification_failed');
  }
  return body;
}

export async function requestAccountDeletion({ config, accessToken, fetchImpl = fetch }) {
  const safe = validatePublicConfig(config);
  const response = await fetchImpl(`${safe.supabaseUrl}/functions/v1/delete-account`, {
    method: 'POST',
    headers: {
      apikey: safe.anonKey,
      Authorization: `Bearer ${accessToken}`,
      'Content-Type': 'application/json',
      Accept: 'application/json',
    },
    body: JSON.stringify({ confirmation: 'delete-my-account' }),
    cache: 'no-store',
    credentials: 'omit',
  });
  const body = await response.json().catch(() => ({}));
  if (!response.ok) {
    const code = typeof body.error === 'string' ? body.error : 'account_deletion_failed';
    throw new Error(code);
  }
  if (body?.deleted !== true || body?.status !== 'deleted') {
    throw new Error('deletion_not_confirmed');
  }
  return body;
}

function maskedIdentity(user) {
  const email = typeof user?.email === 'string' ? user.email : '';
  if (!email.includes('@')) return 'your authenticated Google account';
  const [local, domain] = email.split('@');
  const visible = local.slice(0, Math.min(2, local.length));
  return `${visible}${local.length > 2 ? '***' : ''}@${domain}`;
}

function getConfig() {
  return validatePublicConfig(globalThis.HOME_PILOT_ACCOUNT_DELETION_CONFIG);
}

function setStatus(element, message, kind = 'info') {
  if (!element) return;
  element.textContent = message;
  element.dataset.kind = kind;
}

async function initializePage() {
  const btnAuth = document.getElementById('btn-authenticate');
  const btnDelete = document.getElementById('btn-delete');
  const statusEl = document.getElementById('deletion-status');
  const identityEl = document.getElementById('authenticated-identity');

  let config;
  try {
    config = getConfig();
  } catch (_) {
    setStatus(
      statusEl,
      'Account deletion is temporarily unavailable because this page is not configured. Please use the in-app deletion flow or contact support.',
      'error',
    );
    if (btnAuth) btnAuth.disabled = true;
    return;
  }

  let accessToken = accessTokenFromLocation(globalThis.location);
  if (accessToken) {
    sessionStorage.setItem(TOKEN_KEY, accessToken);
    history.replaceState(null, document.title, `${location.pathname}${location.search}`);
  } else {
    accessToken = sessionStorage.getItem(TOKEN_KEY);
  }

  if (accessToken) {
    try {
      const user = await fetchAuthenticatedUser({ config, accessToken });
      setStatus(statusEl, 'Identity verified. Review the deletion details before continuing.', 'success');
      if (identityEl) identityEl.textContent = `Signed in as ${maskedIdentity(user)}`;
      if (btnAuth) btnAuth.hidden = true;
      if (btnDelete) {
        btnDelete.hidden = false;
        btnDelete.disabled = false;
      }
    } catch (_) {
      sessionStorage.removeItem(TOKEN_KEY);
      accessToken = null;
      setStatus(statusEl, 'Your verification session is invalid or expired. Sign in again to continue.', 'error');
    }
  }

  btnAuth?.addEventListener('click', () => {
    setStatus(statusEl, 'Opening Google sign-in…');
    globalThis.location.assign(buildGoogleAuthorizeUrl(config));
  });

  btnDelete?.addEventListener('click', async () => {
    if (!accessToken) {
      setStatus(statusEl, 'Sign in with Google before requesting deletion.', 'error');
      return;
    }
    const confirmed = globalThis.confirm(
      'Permanently delete your HomePilot cloud account and associated synchronized data? This action cannot be undone.',
    );
    if (!confirmed) {
      setStatus(statusEl, 'Deletion cancelled. No account data was deleted.');
      return;
    }

    btnDelete.disabled = true;
    setStatus(statusEl, 'Deleting your HomePilot cloud account…');
    try {
      await requestAccountDeletion({ config, accessToken });
      sessionStorage.removeItem(TOKEN_KEY);
      accessToken = null;
      if (identityEl) identityEl.textContent = '';
      btnDelete.hidden = true;
      setStatus(
        statusEl,
        'Account deletion confirmed. Your HomePilot cloud account and associated synchronized data were deleted.',
        'success',
      );
    } catch (error) {
      const code = error instanceof Error ? error.message : 'account_deletion_failed';
      const message = code === 'recent_reauthentication_required'
        ? 'A fresh Google sign-in is required. Sign in again, then retry deletion.'
        : 'HomePilot could not confirm account deletion. Nothing on this page will claim deletion succeeded; please retry or contact support.';
      if (code === 'authentication_verification_failed' || code === 'recent_reauthentication_required') {
        sessionStorage.removeItem(TOKEN_KEY);
        accessToken = null;
        btnAuth.hidden = false;
      }
      btnDelete.disabled = false;
      setStatus(statusEl, message, 'error');
    }
  });
}

if (typeof document !== 'undefined') {
  document.addEventListener('DOMContentLoaded', () => {
    void initializePage();
  });
}
