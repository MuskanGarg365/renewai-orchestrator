import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import Home from './Home';
import portfolioFixture from '@/api/fixtures/portfolio.json';
import { RenewAIApiError } from '@/api/renewaiClient';

const getPortfolio = vi.fn();
const getAudit = vi.fn();

vi.mock('@/api/renewaiClient', async importOriginal => {
  const actual = await importOriginal<typeof import('@/api/renewaiClient')>();
  return {
    ...actual,
    getPortfolio: (...args: unknown[]) => getPortfolio(...args),
    getAudit: (...args: unknown[]) => getAudit(...args),
  };
});

describe('Home dashboard', () => {
  beforeEach(() => {
    getPortfolio.mockReset();
    getAudit.mockReset();
    getAudit.mockResolvedValue({
      success: true,
      correlationId: 'RENEWAI-AUDIT',
      canApprove: false,
      rows: [],
    });
  });

  it('shows KPIs, batteries and assets from the API', async () => {
    getPortfolio.mockResolvedValue(portfolioFixture);
    render(<Home />);

    expect(screen.getByRole('status', { name: /loading/i })).toBeInTheDocument();
    expect(await screen.findByTestId('kpi-solar')).toBeInTheDocument();
    expect(screen.getByTestId('kpi-demand-gap')).toBeInTheDocument();
    expect(screen.getByTestId('kpi-price')).toHaveTextContent('3,050');
    expect(screen.getByTestId('battery-BATTERY_MH_01')).toBeInTheDocument();
    expect(screen.getByText('Maharashtra Solar Farm 1')).toBeInTheDocument();
    expect(screen.getByTestId('data-quality')).toHaveTextContent(/data quality ok/i);
  });

  it('shows a forbidden state and retries', async () => {
    getPortfolio
      .mockRejectedValueOnce(new RenewAIApiError('Access denied.', 'forbidden', 403, 'RENEWAI-X'))
      .mockResolvedValueOnce(portfolioFixture);
    render(<Home />);

    expect(await screen.findByTestId('error-view')).toHaveTextContent(/cannot read/i);
    expect(screen.getByTestId('error-view')).toHaveTextContent('RENEWAI-X');

    await userEvent.click(screen.getByRole('button', { name: /retry/i }));
    await waitFor(() => expect(screen.getByTestId('kpi-solar')).toBeInTheDocument());
  });

  it('shows the empty state when no assets return', async () => {
    getPortfolio.mockResolvedValue({ ...portfolioFixture, assets: [] });
    render(<Home />);
    expect(await screen.findByTestId('empty-view')).toBeInTheDocument();
  });
});