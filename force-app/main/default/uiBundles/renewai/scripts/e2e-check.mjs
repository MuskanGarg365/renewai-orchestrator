/**
 * End-to-end story through the live REST API, one run, with timings.
 *   node scripts/e2e-check.mjs <org-alias> [asOf] [--json out.json]
 *
 * Story: portfolio -> decision -> (approval needed?) -> approve -> audit,
 * plus the failure paths a reviewer will ask about.
 */
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

const args = process.argv.slice(2);
const jsonIdx = args.indexOf('--json');
const jsonOut = jsonIdx >= 0 ? args[jsonIdx + 1] : null;
const positional = args.filter((a, i) => a !== '--json' && i !== jsonIdx + 1);
const alias = positional[0];
const asOf = positional[1] ?? '2026-10-09T06:30:00Z';
if (!alias) {
  console.error('Usage: node scripts/e2e-check.mjs <org-alias> [asOf] [--json out.json]');
  process.exit(1);
}

const BASE = '/services/apexrest/renewai/v1';
const timings = [];

function call(method, path, payload) {
  const cli = ['api', 'request', 'rest', `${BASE}${path}`, '-o', alias];
  if (method === 'POST') cli.push('--method', 'POST', '--body', JSON.stringify(payload));
  const started = Date.now();
  let text;
  try {
    text = execFileSync('sf', cli, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  } catch (e) {
    text = `${e.stdout ?? ''}${e.stderr ?? ''}`;
  }
  const ms = Date.now() - started;
  const start = text.indexOf('{');
  let body = {};
  try {
    body = JSON.parse(start >= 0 ? text.slice(start) : text);
  } catch {
    body = { raw: text.slice(0, 300) };
  }
  timings.push({ step: `${method} ${path.split('?')[0]}`, ms });
  return body;
}

const failures = [];
const check = (ok, msg) =>
  ok ? console.log('PASS', msg) : (failures.push(msg), console.error('FAIL', msg));

// 1. Data is readable
const portfolio = call('GET', `/portfolio?asOf=${encodeURIComponent(asOf)}&intervalMinutes=15&maximumAgeMinutes=30`);
check(portfolio.success === true, 'portfolio loads');

// 2. A decision that needs no approval is saved as such
const balanced = call('POST', '/decision', { asOf, objectiveMode: 'Balanced' });
check(balanced.success === true && !!balanced.decisionId, 'Balanced decision saved');
check(typeof balanced.correlationId === 'string', 'Balanced decision has a correlation id');

// 3. Cost First is the demo case that needs a person
const costFirst = call('POST', '/decision', { asOf, objectiveMode: 'Cost First' });
check(costFirst.success === true, 'Cost First decision saved');
check(costFirst.approvalStatus === 'Pending', 'Cost First is Pending approval');

// 4. Failure paths before the approval
const badOutcome = call('POST', '/decision/approval', { decisionId: costFirst.decisionId, outcome: 'Maybe' });
check(badOutcome.errorCode === 'VALIDATION_ERROR', 'bad outcome is a 400 VALIDATION_ERROR');
const noNote = call('POST', '/decision/approval', { decisionId: costFirst.decisionId, outcome: 'Rejected' });
check(noNote.errorCode === 'VALIDATION_ERROR', 'rejecting without a note is refused');

// 5. Approve, then prove it is recorded and cannot be repeated
const approved = call('POST', '/decision/approval', {
  decisionId: costFirst.decisionId,
  outcome: 'Approved',
  note: 'e2e-check',
});
if (approved.errorCode === 'APPROVAL_NOT_PERMITTED') {
  check(false, 'approval refused: assign RenewAI_Approver to this user (or run the check as an approver)');
} else {
  check(approved.approvalStatus === 'Approved', 'approval saved');
  check(approved.actionsUpdated >= 1, 'actions moved out of Awaiting Approval');
  const again = call('POST', '/decision/approval', { decisionId: costFirst.decisionId, outcome: 'Approved' });
  check(again.errorCode === 'VALIDATION_ERROR', 'a second approval is refused (NOT_PENDING)');
}

// 6. Audit trail shows the decision with who decided
const audit = call('GET', '/decisions?limit=10');
check(audit.success === true && Array.isArray(audit.rows), 'audit trail loads');
const row = (audit.rows ?? []).find(r => r.decisionId === costFirst.decisionId);
check(!!row, 'audit trail contains the Cost First decision');
if (approved.approvalStatus === 'Approved') {
  check(row?.approvalStatus === 'Approved' && !!row?.decidedBy, 'audit shows Approved and who decided');
}
const filtered = call('GET', '/decisions?status=Bogus');
check(filtered.errorCode === 'VALIDATION_ERROR', 'audit rejects an unknown status filter');

// 7. Bad input is a structured error, never a crash
const badMode = call('POST', '/decision', { asOf, objectiveMode: 'Nonsense' });
check(typeof badMode.errorCode === 'string' && typeof badMode.correlationId === 'string', 'invalid mode returns a structured error with a correlation id');
const stale = call('POST', '/decision', { asOf: '2020-01-01T00:00:00Z', objectiveMode: 'Balanced' });
check(typeof stale.errorCode === 'string', 'a time with no data returns a structured error');

console.log('\nTimings (ms):');
for (const t of timings) console.log(`  ${String(t.ms).padStart(6)}  ${t.step}`);
if (jsonOut) {
  writeFileSync(jsonOut, JSON.stringify({ alias, asOf, ranAt: new Date().toISOString(), failures, timings }, null, 2));
  console.log(`Wrote ${jsonOut}`);
}

if (failures.length) {
  console.error(`\n${failures.length} check(s) failed.`);
  process.exit(1);
}
console.log('\nAll end-to-end checks passed.');
