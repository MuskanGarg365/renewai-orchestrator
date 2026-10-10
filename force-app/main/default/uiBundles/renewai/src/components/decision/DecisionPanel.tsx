import { useState } from 'react';
import { DATA_MODE } from '@/config';
import { useDecision } from '@/hooks/useDecision';
import { OBJECTIVE_MODES, type ObjectiveMode } from '@/api/renewaiTypes';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { StatusAlert } from '@/components/alerts/status-alert';
import { ScoreBreakdown } from './ScoreBreakdown';

export function DecisionPanel() {
  const [objective, setObjective] = useState<ObjectiveMode>('Balanced');
  const { status, data, error, run } = useDecision(DATA_MODE);

  return (
    <section aria-label="Decision engine" className="space-y-4">
      <div className="flex flex-wrap items-end justify-between gap-3">
        <div>
          <h2 className="text-lg font-semibold">Decision engine</h2>
          <p className="text-muted-foreground text-sm">
            Deterministic Apex engine. Every setpoint below comes from the
            engine, not from AI.
          </p>
        </div>
        <div className="flex items-center gap-2">
          <label className="text-sm" htmlFor="objective-mode">
            Objective
          </label>
          <select
            id="objective-mode"
            className="border-input bg-background h-9 rounded-md border px-2 text-sm"
            value={objective}
            onChange={e => setObjective(e.target.value as ObjectiveMode)}
          >
            {OBJECTIVE_MODES.map(m => (
              <option key={m} value={m}>
                {m}
              </option>
            ))}
          </select>
          <Button onClick={() => run(objective)} disabled={status === 'running'}>
            {status === 'running' ? 'Running…' : 'Run decision'}
          </Button>
        </div>
      </div>

      {status === 'error' && error && (
        <StatusAlert variant="error">
          {error.message}
          {error.correlationId ? ` (Correlation ID: ${error.correlationId})` : ''}
        </StatusAlert>
      )}

      {status === 'done' && data && (
        <div className="space-y-4" data-testid="decision-result">
          <Card>
            <CardHeader>
              <div className="flex flex-wrap items-center justify-between gap-2">
                <CardTitle className="text-base" data-testid="decision-label">
                  {data.selected.label}
                </CardTitle>
                <div className="flex flex-wrap items-center gap-2">
                  <Badge variant="secondary">{data.objectiveMode}</Badge>
                  <Badge
                    variant={
                      data.approvalStatus === 'Pending' ? 'destructive' : 'outline'
                    }
                    data-testid="approval-status"
                  >
                    {data.approvalStatus === 'Pending'
                      ? 'Approval required'
                      : 'No approval needed'}
                  </Badge>
                  <Badge variant="outline">
                    Confidence {Math.round(data.confidence * 100)}%
                  </Badge>
                </div>
              </div>
            </CardHeader>
            <CardContent className="space-y-4">
              <p className="text-sm" data-testid="decision-explanation">
                {data.explanation}
              </p>
              <p className="text-muted-foreground text-xs">
                Correlation ID: {data.correlationId} · Decision: {data.decisionId} ·
                Score {data.selected.score?.toFixed(4)} · Reserve target{' '}
                {data.reserveMW} MW
              </p>

              <div className="grid gap-6 md:grid-cols-2">
                <div>
                  <h3 className="mb-2 text-sm font-semibold">Selected actions</h3>
                  <Table>
                    <TableHeader>
                      <TableRow>
                        <TableHead>Action</TableHead>
                        <TableHead>Asset</TableHead>
                        <TableHead className="text-right">MW</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {data.selected.actions.length === 0 && (
                        <TableRow>
                          <TableCell colSpan={3}>No action required</TableCell>
                        </TableRow>
                      )}
                      {data.selected.actions.map(a => (
                        <TableRow key={`${a.actionType}-${a.assetCode}`}>
                          <TableCell>{a.actionType}</TableCell>
                          <TableCell>{a.assetCode}</TableCell>
                          <TableCell className="text-right">
                            {a.quantityMW.toFixed(2)}
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                </div>
                <div>
                  <h3 className="mb-2 text-sm font-semibold">
                    Score breakdown (lower is better)
                  </h3>
                  <ScoreBreakdown terms={data.selected.breakdown} />
                </div>
              </div>
            </CardContent>
          </Card>

          <div className="grid gap-4 md:grid-cols-2">
            <Card size="sm">
              <CardHeader>
                <CardTitle className="text-sm">Other feasible candidates</CardTitle>
              </CardHeader>
              <CardContent>
                <ol className="space-y-1 text-sm" data-testid="alternatives">
                  {data.alternatives.map(c => (
                    <li key={c.candidateId} className="flex justify-between gap-2">
                      <span>
                        {c.rank}. {c.label}
                      </span>
                      <span className="text-muted-foreground">
                        {c.score?.toFixed(4)}
                      </span>
                    </li>
                  ))}
                </ol>
              </CardContent>
            </Card>
            <Card size="sm">
              <CardHeader>
                <CardTitle className="text-sm">Rejected by hard constraints</CardTitle>
              </CardHeader>
              <CardContent>
                {data.rejected.length === 0 ? (
                  <p className="text-muted-foreground text-sm">
                    No candidates were rejected.
                  </p>
                ) : (
                  <ul className="space-y-1 text-sm" data-testid="rejected">
                    {data.rejected.map(c => (
                      <li key={c.candidateId}>
                        {c.label}{' '}
                        <span className="text-destructive">
                          ({c.rejectionReasons.join(', ')})
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </CardContent>
            </Card>
          </div>
        </div>
      )}
    </section>
  );
}
