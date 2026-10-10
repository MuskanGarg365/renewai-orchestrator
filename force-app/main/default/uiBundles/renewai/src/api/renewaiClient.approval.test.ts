import { beforeEach, describe, expect, it } from 'vitest';
import {
  approveDecision,
  getAudit,
  resetFixtureAudit,
  runDecision,
  RenewAIApiError,
} from './renewaiClient';
import { setOutageSimulated } from '@/lib/demoControls';

describe('fixture approval flow', () => {
  beforeEach(() => {
    resetFixtureAudit();
    setOutageSimulated(false);
  });

  it('records a Pending decision, then approves it once', async () => {
    const d = await runDecision('Cost First', 'fixture');
    expect(d.approvalStatus).toBe('Pending');

    const pending = await getAudit('Pending', 'fixture');
    expect(pending.rows).toHaveLength(1);
    expect(pending.rows[0].decisionId).toBe(d.decisionId);

    const out = await approveDecision(d.decisionId, 'Approved', 'ok', 'fixture');
    expect(out.approvalStatus).toBe('Approved');
    expect((await getAudit('Pending', 'fixture')).rows).toHaveLength(0);
    expect((await getAudit('Approved', 'fixture')).rows[0].decidedBy).toBe(
      'Demo approver'
    );

    await expect(
      approveDecision(d.decisionId, 'Approved', '', 'fixture')
    ).rejects.toThrow(/NOT_PENDING/);
  });

  it('needs a note to reject', async () => {
    const d = await runDecision('Cost First', 'fixture');
    await expect(
      approveDecision(d.decisionId, 'Rejected', '  ', 'fixture')
    ).rejects.toThrow(/NOTE_REQUIRED/);
    const out = await approveDecision(d.decisionId, 'Rejected', 'Too risky', 'fixture');
    expect(out.approvalStatus).toBe('Rejected');
  });

  it('does not list decisions that need no approval as Pending', async () => {
    await runDecision('Balanced', 'fixture');
    expect((await getAudit('Pending', 'fixture')).rows).toHaveLength(0);
    expect((await getAudit(undefined, 'fixture')).rows).toHaveLength(1);
  });

  it('fails like a real outage when the demo switch is on', async () => {
    setOutageSimulated(true);
    const attempt = runDecision('Balanced', 'fixture');
    await expect(attempt).rejects.toBeInstanceOf(RenewAIApiError);
    await expect(attempt).rejects.toMatchObject({
      correlationId: 'RENEWAI-SIMULATED',
    });
    setOutageSimulated(false);
  });
});
