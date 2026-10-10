import { useState } from 'react';
import { DATA_MODE } from '@/config';
import { useAudit } from '@/hooks/useAudit';
import type { ApprovalStatus } from '@/api/renewaiTypes';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent } from '@/components/ui/card';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { StatusAlert } from '@/components/alerts/status-alert';

const FILTERS: Array<ApprovalStatus | ''> = [
  '',
  'Pending',
  'Approved',
  'Rejected',
  'Not Required',
];

function variantFor(status: ApprovalStatus) {
  if (status === 'Pending') return 'destructive' as const;
  if (status === 'Approved') return 'default' as const;
  return 'outline' as const;
}

/** Audit trail: who decided what, when, with which correlation id. */
export function AuditPanel({ refreshKey = 0 }: { refreshKey?: number }) {
  const [filter, setFilter] = useState<ApprovalStatus | ''>('');
  const { loading, data, error, reload } = useAudit(
    DATA_MODE,
    filter || undefined,
    refreshKey
  );

  return (
    <section aria-label="Audit trail" className="space-y-3">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">Audit trail</h2>
          <p className="text-muted-foreground text-sm">
            Every saved decision, its approval state and who decided.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <label className="text-sm" htmlFor="audit-filter">
            Status
          </label>
          <select
            id="audit-filter"
            className="border-input bg-background h-9 rounded-md border px-2 text-sm"
            value={filter}
            onChange={e => setFilter(e.target.value as ApprovalStatus | '')}
          >
            {FILTERS.map(f => (
              <option key={f || 'all'} value={f}>
                {f || 'All'}
              </option>
            ))}
          </select>
          <Button variant="outline" onClick={() => void reload()} disabled={loading}>
            {loading ? 'Loading…' : 'Refresh'}
          </Button>
        </div>
      </div>

      {error && (
        <StatusAlert variant="error">
          {error.kind === 'forbidden'
            ? 'You cannot read the audit trail. Assign RenewAI_Audit_Access.'
            : error.message}
          {error.correlationId ? ` (Correlation ID: ${error.correlationId})` : ''}
        </StatusAlert>
      )}

      <Card size="sm">
        <CardContent>
          <Table data-testid="audit-table">
            <TableHeader>
              <TableRow>
                <TableHead>Decision</TableHead>
                <TableHead>Objective</TableHead>
                <TableHead>Status</TableHead>
                <TableHead>Decided by</TableHead>
                <TableHead>Note</TableHead>
                <TableHead>Correlation ID</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data && data.rows.length === 0 && (
                <TableRow>
                  <TableCell colSpan={6}>No decisions yet.</TableCell>
                </TableRow>
              )}
              {data?.rows.map(row => (
                <TableRow key={row.decisionId} data-testid={`audit-${row.decisionId}`}>
                  <TableCell>
                    {row.name}
                    <div className="text-muted-foreground text-xs">
                      {row.decisionType} · {row.actionCount} action(s)
                    </div>
                  </TableCell>
                  <TableCell>{row.objectiveMode}</TableCell>
                  <TableCell>
                    <Badge variant={variantFor(row.approvalStatus)}>
                      {row.approvalStatus}
                    </Badge>
                  </TableCell>
                  <TableCell>{row.decidedBy ?? '—'}</TableCell>
                  <TableCell>{row.approvalNote ?? '—'}</TableCell>
                  <TableCell className="text-xs">{row.correlationId ?? '—'}</TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </CardContent>
      </Card>
    </section>
  );
}
