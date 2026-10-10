import { useCallback, useState } from 'react';
import { runDecision, RenewAIApiError } from '@/api/renewaiClient';
import type { DecisionResponse, ObjectiveMode } from '@/api/renewaiTypes';
import type { DataMode } from '@/config';

export type DecisionStatus = 'idle' | 'running' | 'done' | 'error';

export interface DecisionState {
  status: DecisionStatus;
  data: DecisionResponse | null;
  error: RenewAIApiError | null;
  run: (objectiveMode: ObjectiveMode) => Promise<void>;
}

/** Runs a decision on demand (button click), unlike usePortfolio which loads on mount. */
export function useDecision(mode: DataMode): DecisionState {
  const [status, setStatus] = useState<DecisionStatus>('idle');
  const [data, setData] = useState<DecisionResponse | null>(null);
  const [error, setError] = useState<RenewAIApiError | null>(null);

  const run = useCallback(
    async (objectiveMode: ObjectiveMode) => {
      setStatus('running');
      setError(null);
      try {
        const result = await runDecision(objectiveMode, mode);
        setData(result);
        setStatus('done');
      } catch (err) {
        console.error(err);
        setError(
          err instanceof RenewAIApiError
            ? err
            : new RenewAIApiError('Unexpected error.', 'server')
        );
        setStatus('error');
      }
    },
    [mode]
  );

  return { status, data, error, run };
}
