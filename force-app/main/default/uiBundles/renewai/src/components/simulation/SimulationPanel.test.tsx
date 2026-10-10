import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { SimulationPanel } from './SimulationPanel';
import simulationFixtures from '@/api/fixtures/simulations.json';
import { RenewAIApiError } from '@/api/renewaiClient';

const runSimulation = vi.fn();
const cancelSimulation = vi.fn();

vi.mock('@/api/renewaiClient', async importOriginal => {
  const actual = await importOriginal<typeof import('@/api/renewaiClient')>();
  return {
    ...actual,
    runSimulation: (...args: unknown[]) => runSimulation(...args),
    cancelSimulation: (...args: unknown[]) => cancelSimulation(...args),
  };
});

describe('SimulationPanel', () => {
  beforeEach(() => {
    runSimulation.mockReset();
    cancelSimulation.mockReset();
  });

  it('runs a simulation and shows the timeline, KPIs and objective comparison', async () => {
    runSimulation.mockResolvedValue(simulationFixtures['Cloud Front']);
    render(<SimulationPanel />);

    await userEvent.click(screen.getByRole('button', { name: /run simulation/i }));

    expect(await screen.findByTestId('simulation-result')).toBeInTheDocument();
    expect(runSimulation.mock.calls[0][0]).toBe('Cloud Front');
    expect(runSimulation.mock.calls[0][1]).toBe('Balanced');

    // eight intervals, with the action cluster changing over time
    const rows = within(screen.getByTestId('sim-timeline')).getAllByRole('row');
    expect(rows).toHaveLength(9); // header + 8 steps
    expect(screen.getByTestId('sim-timeline')).toHaveTextContent(/balance with the grid/i);
    expect(screen.getByTestId('sim-timeline')).toHaveTextContent(/cover the gap/i);

    expect(screen.getByTestId('kpi-cost')).toHaveTextContent('₹');
    expect(screen.getByTestId('sim-checksum')).toHaveTextContent(
      simulationFixtures['Cloud Front'].primary.checksum
    );

    // four objectives compared, the chosen one marked
    const comparison = within(screen.getByTestId('sim-comparison'));
    expect(comparison.getAllByRole('row')).toHaveLength(5);
    expect(comparison.getByText('Selected')).toBeInTheDocument();
  });

  it('follows the scenario default objective when the scenario changes', async () => {
    render(<SimulationPanel />);

    await userEvent.selectOptions(screen.getByLabelText(/scenario/i), 'Price Spike');

    expect(screen.getByLabelText(/objective/i)).toHaveValue('Cost First');
  });

  it('can be cancelled while it is running', async () => {
    runSimulation.mockImplementation(
      () => new Promise(() => {}) // never resolves
    );
    render(<SimulationPanel />);

    await userEvent.click(screen.getByRole('button', { name: /run simulation/i }));
    await userEvent.click(await screen.findByRole('button', { name: /^cancel$/i }));

    expect(await screen.findByRole('status')).toHaveTextContent(/cancelled/i);
    expect(screen.queryByTestId('simulation-result')).not.toBeInTheDocument();
  });

  it('marks a finished run as cancelled in Salesforce when it is discarded', async () => {
    runSimulation.mockResolvedValue(simulationFixtures['Battery Outage']);
    cancelSimulation.mockResolvedValue({
      success: true,
      correlationId: 'RENEWAI-X',
      scenarioId: simulationFixtures['Battery Outage'].scenarioId,
      status: 'Cancelled',
    });
    render(<SimulationPanel />);

    await userEvent.click(screen.getByRole('button', { name: /run simulation/i }));
    await userEvent.click(await screen.findByRole('button', { name: /discard run/i }));

    expect(cancelSimulation.mock.calls[0][0]).toBe(
      simulationFixtures['Battery Outage'].scenarioId
    );
    expect(await screen.findByRole('status')).toHaveTextContent(/marked cancelled/i);
  });

  it('shows the structured error and correlation id when the run fails', async () => {
    runSimulation.mockImplementation(() =>
      Promise.reject(new RenewAIApiError('Simulation failed.', 'server', 500, 'RENEWAI-ERR3'))
    );
    render(<SimulationPanel />);

    await userEvent.click(screen.getByRole('button', { name: /run simulation/i }));

    expect(await screen.findByRole('alert')).toHaveTextContent('RENEWAI-ERR3');
  });
});
