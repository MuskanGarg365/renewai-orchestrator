import { useState } from 'react';
import { DATA_MODE } from '@/config';
import { approveDecision, RenewAIApiError } from '@/api/renewaiClient';
import type { ApprovalOutcome, ApprovalResponse } from '@/api/renewaiTypes';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { StatusAlert } from '@/components/alerts/status-alert';

interface Props {
  decisionId: string;
  onDecided?: (result: ApprovalResponse) => void;
}

/** Approve / Reject controls for a decision that is Pending. */
export function ApprovalBar({ decisionId, onDecided }: Props) {
  const [note, setNote] = useState('');
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<ApprovalResponse | null>(null);
  const [error, setError] = useState<RenewAIApiError | null>(null);

  async function decide(outcome: ApprovalOutcome) {
    setBusy(true);
    setError(null);
    try {
      const response = await approveDecision(decisionId, outcome, note, DATA_MODE);
      setResult(response);
      onDecided?.(response);
    } catch (err) {
      console.error(err);
      setError(
        err instanceof RenewAIApiError
          ? err
          : new RenewAIApiError('Unexpected error.', 'server')
      );
    } finally {
      setBusy(false);
    }
  }

  if (result) {
    return (
      <div className="space-y-1" data-testid="approval-result">
        <Badge variant={result.approvalStatus === 'Approved' ? 'default' : 'destructive'}>
          {result.approvalStatus} by {result.decidedBy}
        </Badge>
        <p className="text-muted-foreground text-xs">
          {result.actionsUpdated} action(s) updated · Correlation ID:{' '}
          {result.correlationId}
        </p>
      </div>
    );
  }

  return (
    <div className="space-y-2" data-testid="approval-bar">
      <p className="text-sm font-medium">
        A person must approve this plan before it can run.
      </p>
      <div className="flex flex-wrap items-center gap-2">
        <label className="sr-only" htmlFor={`note-${decisionId}`}>
          Approval note
        </label>
        <input
          id={`note-${decisionId}`}
          className="border-input bg-background h-9 min-w-64 flex-1 rounded-md border px-2 text-sm"
          placeholder="Note (required to reject)"
          maxLength={255}
          value={note}
          onChange={e => setNote(e.target.value)}
        />
        <Button disabled={busy} onClick={() => decide('Approved')}>
          Approve
        </Button>
        <Button
          variant="outline"
          disabled={busy}
          onClick={() => decide('Rejected')}
        >
          Reject
        </Button>
      </div>
      {error && (
        <StatusAlert variant="error">
          {error.kind === 'forbidden'
            ? 'You do not have permission to approve decisions (APPROVAL_NOT_PERMITTED).'
            : error.message}
          {error.correlationId ? ` (Correlation ID: ${error.correlationId})` : ''}
        </StatusAlert>
      )}
    </div>
  );
}
