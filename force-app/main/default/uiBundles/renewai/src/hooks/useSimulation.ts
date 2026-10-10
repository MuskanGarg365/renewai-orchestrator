import { useCallback, useRef, useState } from 'react';
import {
  cancelSimulation,
  runSimulation,
  RenewAIApiError,
} from '@/api/renewaiClient';
import type {
  ObjectiveMode,
  ScenarioType,
  SimulationResponse,
} from '@/api/renewaiTypes';
import type { DataMode } from '@/config';

export type SimulationStatus =
  | 'idle'
  | 'running'
  | 'done'
  | 'error'
  | 'cancelled';

export interface SimulationState {
  status: SimulationStatus;
  data: SimulationResponse | null;
  error: RenewAIApiError | null;
  run: (type: ScenarioType, objectiveMode?: ObjectiveMode) => Promise<void>;
  /** While running: stop waiting. After a run: mark the saved scenario Cancelled. */
  cancel: () => Promise<void>;
}

export function useSimulation(mode: DataMode): SimulationState {
  const [status, setStatus] = useState<SimulationStatus>('idle');
  const [data, setData] = useState<SimulationResponse | null>(null);
  const [error, setError] = useState<RenewAIApiError | null>(null);
  const controller = useRef<AbortController | null>(null);

  const run = useCallback(
    async (type: ScenarioType, objectiveMode?: ObjectiveMode) => {
      const abort = new AbortController();
      controller.current = abort;
      setStatus('running');
      setError(null);
      setData(null);
      try {
        const result = await runSimulation(
          type,
          objectiveMode,
          mode,
          undefined,
          abort.signal
        );
        if (abort.signal.aborted) return; // user cancelled while waiting
        setData(result);
        setStatus('done');
      } catch (err) {
        if (abort.signal.aborted) return;
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

  const cancel = useCallback(async () => {
    if (status === 'running') {
      // A running Apex call cannot be interrupted, so stop waiting for it.
      controller.current?.abort();
      setStatus('cancelled');
      return;
    }
    if (status === 'done' && data) {
      try {
        await cancelSimulation(data.scenarioId, mode);
        setStatus('cancelled');
      } catch (err) {
        console.error(err);
        setError(
          err instanceof RenewAIApiError
            ? err
            : new RenewAIApiError('Unexpected error.', 'server')
        );
        setStatus('error');
      }
    }
  }, [status, data, mode]);

  return { status, data, error, run, cancel };
}
