/**
 * Live API smoke test. The Salesforce CLI makes the calls and handles auth.
 *   node scripts/live-smoke.mjs <org-alias> [asOf]
 */
import { execFileSync } from 'node:child_process';

const alias = process.argv[2];
const asOf = process.argv[3] ?? '2026-10-09T06:30:00Z';
if (!alias) {
  console.error('Usage: node scripts/live-smoke.mjs <org-alias> [asOf]');
  process.exit(1);
}

/** Returns { ok, text } where text is the raw response body (or CLI error output). */
function get(path) {
  try {
    const text = execFileSync(
      'sf',
      ['api', 'request', 'rest', `/services/apexrest/renewai/v1${path}`, '-o', alias],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }
    );
    return { ok: true, text };
  } catch (e) {
    return { ok: false, text: `${e.stdout ?? ''}${e.stderr ?? ''}` };
  }
}

/** POST helper through the CLI. */
function post(path, payload) {
  try {
    const text = execFileSync(
      'sf',
      ['api', 'request', 'rest', `/services/apexrest/renewai/v1${path}`,
       '--method', 'POST', '--body', JSON.stringify(payload), '-o', alias],
      { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }
    );
    return { ok: true, text };
  } catch (e) {
    return { ok: false, text: `${e.stdout ?? ''}${e.stderr ?? ''}` };
  }
}

const failures = [];
const check = (ok, msg) =>
  ok ? console.log('PASS', msg) : (failures.push(msg), console.error('FAIL', msg));

const portfolio = get(
  `/portfolio?asOf=${encodeURIComponent(asOf)}&intervalMinutes=15&maximumAgeMinutes=30`
);
check(portfolio.ok, 'GET /portfolio succeeded');

let p = {};
try {
  p = JSON.parse(portfolio.text);
} catch {
  console.error('  Response was not JSON:', portfolio.text.slice(0, 300));
}

check(p.success === true, 'success flag');
check(typeof p.correlationId === 'string', 'correlationId present');
check(p.assets?.length === 12, `12 assets (got ${p.assets?.length})`);
check(p.metrics?.renewableTotalMW > 0, `renewableTotalMW ${p.metrics?.renewableTotalMW}`);
check(p.metrics?.energyPriceMWh != null, `energyPriceMWh ${p.metrics?.energyPriceMWh}`);

// Day 5: decision engine
for (const mode of ['Balanced', 'Cost First']) {
  const d = post('/decision', { asOf, objectiveMode: mode });
  let body = {};
  try { body = JSON.parse(d.text); } catch { console.error('  Not JSON:', d.text.slice(0, 300)); }
  check(body.success === true, `POST /decision (${mode}) succeeded`);
  check(typeof body.decisionId === 'string', `${mode}: decision saved (${body.decisionId})`);
  check(body.selected?.actions?.length > 0, `${mode}: ${body.selected?.candidateId} with ${body.selected?.actions?.length} actions`);
}

// Negative test: a timestamp not on a 15-minute boundary must be rejected.
const bad = get('/portfolio?asOf=2026-10-09T06:31:00Z');
check(
  !bad.ok && bad.text.includes('INTERVAL_MISALIGNED'),
  'misaligned asOf is rejected with INTERVAL_MISALIGNED'
);

if (failures.length) process.exit(1);