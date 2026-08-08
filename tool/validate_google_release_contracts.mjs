import fs from 'node:fs';

function read(path) {
  return fs.readFileSync(path, 'utf8');
}

function requireMatch(condition, message) {
  if (!condition) throw new Error(message);
}

const manifest = read('android/app/src/main/AndroidManifest.xml');
const gradle = read('android/app/build.gradle.kts');
const gitignore = read('.gitignore');
const monetization = read('lib/src/features/monetization/monetization.dart');
const runtime = read('lib/src/features/monetization/ad_runtime.dart');
const deletion = read('download-site/account-deletion.js');

requireMatch(/SCHEDULE_EXACT_ALARM/.test(manifest), 'SCHEDULE_EXACT_ALARM must remain intentional');
requireMatch(!/ACCESS_FINE_LOCATION/.test(manifest), 'fine location is forbidden');
requireMatch(!/ACCESS_BACKGROUND_LOCATION/.test(manifest), 'background location is forbidden');
requireMatch(/com\.google\.android\.gms\.ads\.APPLICATION_ID/.test(manifest), 'AdMob application metadata missing');
requireMatch(/targetSdk\s*=\s*36/.test(gradle), 'targetSdk must remain API 36');
requireMatch(/compileSdk\s*=\s*36/.test(gradle), 'compileSdk must remain API 36');
requireMatch(!/firebase-analytics|firebase-bom/i.test(gradle), 'direct Firebase Analytics must not be packaged');
requireMatch(!/com\.google\.gms\.google-services/.test(gradle), 'Google Services plugin must not be conditionally applied');
requireMatch(/android\/app\/google-services\.json/.test(gitignore), 'production google-services.json must be explicitly ignored');
requireMatch(/3940256099942544/.test(monetization), 'Google demo ad IDs missing from non-production path');
requireMatch(/5274007212820203/.test(monetization), 'production AdMob IDs missing from production path');
requireMatch(/Duration\(minutes:\s*55\)/.test(runtime), '55-minute cache safety threshold missing');
requireMatch(/class AdRuntimeEligibility/.test(runtime), 'authoritative ad runtime eligibility model missing');
requireMatch(/class AdRetryPolicy/.test(runtime), 'bounded ad retry policy missing');
requireMatch(!/setTimeout\s*\(/.test(deletion), 'account-deletion page must not simulate backend work with timers');
requireMatch(/functions\/v1\/delete-account/.test(deletion), 'external deletion must call protected backend');
requireMatch(!/service[_-]?role/i.test(deletion), 'browser deletion bundle must never reference service-role credentials');

if (fs.existsSync('android/app/google-services.json.example')) {
  throw new Error('obsolete google-services.json.example must be removed when Firebase Analytics is unused');
}

console.log('Google/Play/release static contracts verified.');
