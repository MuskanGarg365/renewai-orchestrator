import { useCallback, useEffect, useRef, useState } from 'react';
import { getPortfolio, RenewAIApiError } from '@/api/renewaiClient';
import type { PortfolioResponse } from '@/api/renewaiTypes';
import type { DataMode } from '@/config';

export type PortfolioStatus = 'loading' | 'ready' | 'empty' | 'error';

export interface PortfolioState {
  status: PortfolioStatus;
  data: PortfolioResponse | null;
  error: RenewAIApiError | null;
  refreshing: boolean;
  reload: () => void;
}

/** Loads the portfolio once and exposes reload() for the Retry/Refresh buttons. */
export function usePortfolio(mode: DataMode): PortfolioState {
  const [data, setData] = useState<PortfolioResponse | null>(null);
  const [error, setError] = useState<RenewAIApiError | null>(null);
  const [status, setStatus] = useState<PortfolioStatus>('loading');
  const [refreshing, setRefreshing] = useState(false);
  const [tick, setTick] = useState(0);
  const firstLoad = useRef(true);

  useEffect(() => {
    let cancelled = false;
    if (firstLoad.current) setStatus('loading');
    else setRefreshing(true);

    getPortfolio(mode)
      .then(result => {
        if (cancelled) return;
        setData(result);
        setError(null);
        setStatus(result.assets.length === 0 ? 'empty' : 'ready');
      })
      .catch(err => {
        if (cancelled) return;
        console.error(err);
        setError(
          err instanceof RenewAIApiError
            ? err
            : new RenewAIApiError('Unexpected error.', 'server')
        );
        setStatus('error');
      })
      .finally(() => {
        if (cancelled) return;
        firstLoad.current = false;
        setRefreshing(false);
      });

    return () => {
      cancelled = true;
    };
  }, [mode, tick]);

  const reload = useCallback(() => setTick(t => t + 1), []);

  return { status, data, error, refreshing, reload };
}