import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ApprovalBar } from './ApprovalBar';
import { RenewAIApiError } from '@/api/renewaiClient';

const approveDecision = vi.fn();

vi.mock('@/api/renewaiClient', async importOriginal => {
  const actual = await importOriginal<typeof import('@/api/renewaiClient')>();
  return {
    ...actual,
    approveDecision: (...args: unknown[]) => approveDecision(...args),
  };
});

describe('ApprovalBar', () => {
  beforeEach(() => {
    approveDecision.mockReset();
  });

  it('sends the outcome and note, then shows who decided', async () => {
    approveDecision.mockResolvedValue({
      success: true,
      correlationId: 'RENEWAI-OK',
      decisionId: 'a1',
      approvalStatus: 'Approved',
      actionsUpdated: 2,
      decidedBy: 'Vips',
      decidedOn: '2026-10-09T07:00:00Z',
    });
    const onDecided = vi.fn();
    render(<ApprovalBar decisionId="a1" onDecided={onDecided} />);

    await userEvent.type(screen.getByLabelText(/approval note/i), 'Checked');
    await userEvent.click(screen.getByRole('button', { name: /^approve$/i }));

    expect(approveDecision.mock.calls[0].slice(0, 3)).toEqual([
      'a1',
      'Approved',
      'Checked',
    ]);
    expect(await screen.findByTestId('approval-result')).toHaveTextContent(
      /approved by vips/i
    );
    expect(onDecided).toHaveBeenCalledTimes(1);
  });

  it('explains a 403 clearly', async () => {
    approveDecision.mockImplementation(() =>
      Promise.reject(
        new RenewAIApiError('nope', 'forbidden', 403, 'RENEWAI-403')
      )
    );
    render(<ApprovalBar decisionId="a1" />);

    await userEvent.click(screen.getByRole('button', { name: /^approve$/i }));

    const alert = await screen.findByRole('alert');
    expect(alert).toHaveTextContent(/do not have permission/i);
    expect(alert).toHaveTextContent('RENEWAI-403');
    expect(screen.getByTestId('approval-bar')).toBeInTheDocument();
  });
});
