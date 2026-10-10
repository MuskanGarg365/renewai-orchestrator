import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { DecisionPanel } from './DecisionPanel';
import decisionFixtures from '@/api/fixtures/decisions.json';
import { RenewAIApiError } from '@/api/renewaiClient';

const runDecision = vi.fn();

vi.mock('@/api/renewaiClient', async importOriginal => {
  const actual = await importOriginal<typeof import('@/api/renewaiClient')>();
  return {
    ...actual,
    runDecision: (...args: unknown[]) => runDecision(...args),
  };
});

describe('DecisionPanel', () => {
  beforeEach(() => {
    runDecision.mockReset();
  });

  it('runs the selected objective and shows actions, score breakdown and audit ids', async () => {
    runDecision.mockResolvedValue(decisionFixtures['Cost First']);
    render(<DecisionPanel />);

    await userEvent.selectOptions(screen.getByLabelText(/objective/i), 'Cost First');
    await userEvent.click(screen.getByRole('button', { name: /run decision/i }));

    expect(await screen.findByTestId('decision-result')).toBeInTheDocument();
    expect(runDecision.mock.calls[0][0]).toBe('Cost First');
    expect(screen.getByTestId('decision-label')).toHaveTextContent(/discharge at full rating/i);
    expect(screen.getByTestId('approval-status')).toHaveTextContent(/approval required/i);
    expect(screen.getByTestId('score-breakdown').querySelectorAll('[role="progressbar"]')).toHaveLength(6);
    expect(screen.getByText(/RENEWAI-FIXTURE02/)).toBeInTheDocument();
  });

  it('shows the structured error and its correlation id when the call fails', async () => {
    runDecision.mockImplementation(() =>
      Promise.reject(
        new RenewAIApiError('The request failed validation.', 'validation', 400, 'RENEWAI-ERR1')
      )
    );
    render(<DecisionPanel />);

    await userEvent.click(screen.getByRole('button', { name: /run decision/i }));

    expect(await screen.findByRole('alert')).toHaveTextContent('RENEWAI-ERR1');
  });
});
