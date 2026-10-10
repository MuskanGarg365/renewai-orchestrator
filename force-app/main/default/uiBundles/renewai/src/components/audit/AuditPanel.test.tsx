import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AuditPanel } from './AuditPanel';

const getAudit = vi.fn();

vi.mock('@/api/renewaiClient', async importOriginal => {
  const actual = await importOriginal<typeof import('@/api/renewaiClient')>();
  return { ...actual, getAudit: (...args: unknown[]) => getAudit(...args) };
});

const row = {
  decisionId: 'a1',
  name: 'D-0001',
  decisionType: 'Discharge',
  objectiveMode: 'Cost First',
  approvalStatus: 'Approved',
  approvalNote: 'Checked',
  confidence: 55,
  score: 0.2,
  snapshotTime: '2026-10-09T06:30:00Z',
  correlationId: 'RENEWAI-AAA',
  decidedBy: 'Vips',
  decidedOn: '2026-10-09T07:00:00Z',
  createdDate: '2026-10-09T06:59:00Z',
  actionCount: 2,
};

describe('AuditPanel', () => {
  beforeEach(() => {
    getAudit.mockReset();
    getAudit.mockResolvedValue({
      success: true,
      correlationId: 'RENEWAI-A',
      canApprove: true,
      rows: [row],
    });
  });

  it('lists decisions with approver, note and correlation id', async () => {
    render(<AuditPanel />);
    const r = await screen.findByTestId('audit-a1');
    expect(r).toHaveTextContent('Vips');
    expect(r).toHaveTextContent('Checked');
    expect(r).toHaveTextContent('RENEWAI-AAA');
  });

  it('reloads with the chosen status filter', async () => {
    render(<AuditPanel />);
    await screen.findByTestId('audit-a1');
    await userEvent.selectOptions(screen.getByLabelText(/status/i), 'Pending');
    await vi.waitFor(() => expect(getAudit.mock.calls.at(-1)?.[0]).toBe('Pending'));
  });
});
