import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ScenarioPanel } from './ScenarioPanel';
import scenarioFixtures from '@/api/fixtures/scenarios.json';
import { RenewAIApiError } from '@/api/renewaiClient';

const runScenario = vi.fn();

vi.mock('@/api/renewaiClient', async importOriginal => {
  const actual = await importOriginal<typeof import('@/api/renewaiClient')>();
  return {
    ...actual,
    runScenario: (...args: unknown[]) => runScenario(...args),
  };
});

describe('ScenarioPanel', () => {
  beforeEach(() => {
    runScenario.mockReset();
  });

  it('previews the parameters of the selected scenario', async () => {
    render(<ScenarioPanel />);

    expect(screen.getByTestId('scenario-preview')).toHaveTextContent(/solar output −40%/i);
    await userEvent.click(screen.getByRole('button', { name: 'Price Spike' }));
    expect(screen.getByTestId('scenario-preview')).toHaveTextContent(/price \+80%/i);
  });

  it('runs a scenario and shows the before/after comparison', async () => {
    runScenario.mockResolvedValue(scenarioFixtures['Cloud Front']);
    render(<ScenarioPanel />);

    await userEvent.click(screen.getByRole('button', { name: /run cloud front/i }));

    expect(await screen.findByTestId('scenario-result')).toBeInTheDocument();
    expect(runScenario.mock.calls[0][0]).toBe('Cloud Front');
    expect(screen.getByTestId('decision-changed')).toHaveTextContent(/decision changed/i);
    expect(screen.getByText(/Before \(baseline\)/)).toBeInTheDocument();
    expect(screen.getByText(/After \(disturbed\)/)).toBeInTheDocument();
    expect(screen.getByTestId('scenario-params')).toHaveTextContent(/Solar output/);
    expect(screen.getByTestId('scenario-deltas').querySelectorAll('tbody tr')).toHaveLength(10);
  });

  it('shows the structured error when the scenario fails', async () => {
    runScenario.mockImplementation(() =>
      Promise.reject(new RenewAIApiError('Scenario failed.', 'server', 500, 'RENEWAI-ERR2'))
    );
    render(<ScenarioPanel />);

    await userEvent.click(screen.getByRole('button', { name: /run cloud front/i }));

    expect(await screen.findByRole('alert')).toHaveTextContent('RENEWAI-ERR2');
  });
});
