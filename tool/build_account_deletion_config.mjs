import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

export function validateDeletionConfig(env) {
  const supabaseUrl = String(env.HOMEPILOT_SUPABASE_URL || '').replace(/\/$/, '');
  const anonKey = String(env.HOMEPILOT_SUPABASE_ANON_KEY || '');
  const redirectUrl = String(env.HOMEPILOT_ACCOUNT_DELETION_REDIRECT_URL || '');
  if (!/^https:\/\//.test(supabaseUrl)) throw new Error('HOMEPILOT_SUPABASE_URL must be HTTPS');
  if (!anonKey || /service[_-]?role/i.test(anonKey)) {
    throw new Error('HOMEPILOT_SUPABASE_ANON_KEY must be a public publishable/anon key');
  }
  if (!/^https:\/\//.test(redirectUrl)) {
    throw new Error('HOMEPILOT_ACCOUNT_DELETION_REDIRECT_URL must be HTTPS');
  }
  return { supabaseUrl, anonKey, redirectUrl };
}

export function renderDeletionConfig(config) {
  const json = JSON.stringify(config).replaceAll('<', '\\u003c');
  return `// Generated at build/deploy time. Contains public browser configuration only.\n` +
    `globalThis.HOME_PILOT_ACCOUNT_DELETION_CONFIG = Object.freeze(${json});\n`;
}

export function writeDeletionConfig(outputPath, env = process.env) {
  const config = validateDeletionConfig(env);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, renderDeletionConfig(config), 'utf8');
  return config;
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const outputArg = process.argv.indexOf('--output');
  const outputPath = outputArg >= 0 && process.argv[outputArg + 1]
    ? process.argv[outputArg + 1]
    : 'download-site/account-deletion-config.js';
  writeDeletionConfig(outputPath);
  console.log(`Generated public account-deletion config at ${outputPath}`);
}
