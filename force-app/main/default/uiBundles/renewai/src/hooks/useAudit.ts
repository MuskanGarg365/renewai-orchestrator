import { useCallback, useEffect, useState } from 'react';
import { getAudit, RenewAIApiError } from '@/api/renewaiClient';
import type { ApprovalStatus, AuditResponse } from '@/api/renewaiTypes';
import type { DataMode } from '@/config';

export interface AuditState {
  loading: boolean;
  data: AuditResponse | null;
  error: RenewAIApiError | null;
  reload: () => Promise<void>;
}

/** Loads the audit trail on mount and whenever the filter or refreshKey changes. */
export function useAudit(
  mode: DataMode,
  status?: ApprovalStatus,
  refreshKey = 0
): AuditState {
  const [loading, setLoading] = useState(true);
  const [data, setData] = useState<AuditResponse | null>(null);
  const [error, setError] = useState<RenewAIApiError | null>(null);

  const reload = useCallback(async () => {
    setLoading(true);
    setError(null);
    try {
      setData(await getAudit(status, mode));
    } catch (err) {
      console.error(err);
      setError(
        err instanceof RenewAIApiError
          ? err
          : new RenewAIApiError('Unexpected error.', 'server')
      );
    } finally {
      setLoading(false);
    }
  }, [mode, status]);

  useEffect(() => {
    // Loading on mount / filter change is the point of this effect.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void reload();
  }, [reload, refreshKey]);

  return { loading, data, error, reload };
}
