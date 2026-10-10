import { useCallback, useState } from 'react';
import { runScenario, RenewAIApiError } from '@/api/renewaiClient';
import type {
  ObjectiveMode,
  ScenarioResponse,
  ScenarioType,
} from '@/api/renewaiTypes';
import type { DataMode } from '@/config';

export type ScenarioStatus = 'idle' | 'running' | 'done' | 'error';

export interface ScenarioState {
  status: ScenarioStatus;
  data: ScenarioResponse | null;
  error: RenewAIApiError | null;
  run: (type: ScenarioType, objectiveMode?: ObjectiveMode) => Promise<void>;
}

/** Runs a scenario on demand (button click). */
export function useScenario(mode: DataMode): ScenarioState {
  const [status, setStatus] = useState<ScenarioStatus>('idle');
  const [data, setData] = useState<ScenarioResponse | null>(null);
  const [error, setError] = useState<RenewAIApiError | null>(null);

  const run = useCallback(
    async (type: ScenarioType, objectiveMode?: ObjectiveMode) => {
      setStatus('running');
      setError(null);
      try {
        const result = await runScenario(type, objectiveMode, mode);
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
