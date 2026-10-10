import { useState } from 'react';
import { DATA_MODE } from '@/config';
import { useScenario } from '@/hooks/useScenario';
import { SCENARIOS, scenarioInfo } from '@/api/scenarios';
import type { DecisionResponse, ScenarioType } from '@/api/renewaiTypes';
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

function actionSummary(d: DecisionResponse): string {
  if (d.selected.actions.length === 0) return 'No action required';
  return d.selected.actions
    .map(a => `${a.actionType} ${a.quantityMW.toFixed(2)} MW (${a.assetCode})`)
    .join('; ');
}

function fmt(n: number): string {
  return n.toLocaleString('en-IN', { maximumFractionDigits: 2 });
}

function DecisionColumn({
  title,
  decision,
}: {
  title: string;
  decision: DecisionResponse;
}) {
  return (
    <Card size="sm">
      <CardHeader>
        <div className="flex flex-wrap items-center justify-between gap-2">
          <CardTitle className="text-sm">{title}</CardTitle>
          <Badge
            variant={
              decision.approvalStatus === 'Pending' ? 'destructive' : 'outline'
            }
          >
            {decision.approvalStatus === 'Pending'
              ? 'Approval required'
              : 'No approval needed'}
          </Badge>
        </div>
      </CardHeader>
      <CardContent className="space-y-2 text-sm">
        <p className="font-medium">{decision.selected.label}</p>
        <p className="text-muted-foreground">{actionSummary(decision)}</p>
        <p className="text-muted-foreground text-xs">
          Decision {decision.decisionId} · Score{' '}
          {decision.selected.score?.toFixed(4)}
        </p>
      </CardContent>
    </Card>
  );
}

export function ScenarioPanel() {
  const [selected, setSelected] = useState<ScenarioType>('Cloud Front');
  const { status, data, error, run } = useScenario(DATA_MODE);
  const info = scenarioInfo(selected);

  return (
    <section aria-label="Scenarios" className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Scenarios</h2>
        <p className="text-muted-foreground text-sm">
          Inject a scripted disturbance and compare the engine&apos;s decision
          before and after. Parameters are fixed, so every run is repeatable.
        </p>
      </div>

      <div className="flex flex-wrap gap-2" role="group" aria-label="Scenario">
        {SCENARIOS.map(s => (
          <Button
            key={s.type}
            variant={selected === s.type ? 'default' : 'outline'}
            aria-pressed={selected === s.type}
            onClick={() => setSelected(s.type)}
          >
            {s.title}
          </Button>
        ))}
      </div>

      <Card size="sm">
        <CardContent className="flex flex-wrap items-center justify-between gap-3">
          <div className="space-y-1 text-sm">
            <p>{info.description}</p>
            <p className="text-muted-foreground" data-testid="scenario-preview">
              Parameters: {info.preview.join(' · ')} · Objective:{' '}
              {info.defaultMode}
            </p>
          </div>
          <Button
            onClick={() => run(selected, info.defaultMode)}
            disabled={status === 'running'}
          >
            {status === 'running' ? 'Running…' : `Run ${info.title}`}
          </Button>
        </CardContent>
      </Card>

      {status === 'error' && error && (
        <StatusAlert variant="error">
          {error.message}
          {error.correlationId ? ` (Correlation ID: ${error.correlationId})` : ''}
        </StatusAlert>
      )}

      {status === 'done' && data && (
        <div className="space-y-4" data-testid="scenario-result">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="secondary">{data.scenarioType}</Badge>
            <Badge variant="outline">{data.objectiveMode}</Badge>
            <Badge
              variant={data.comparison.decisionChanged ? 'destructive' : 'outline'}
              data-testid="decision-changed"
            >
              {data.comparison.decisionChanged
                ? 'Decision changed'
                : 'Same decision, different quantities'}
            </Badge>
            <span className="text-muted-foreground text-xs">
              Correlation ID: {data.correlationId} · Scenario: {data.scenarioId}
            </span>
          </div>

          <div className="grid gap-4 md:grid-cols-2">
            <DecisionColumn title="Before (baseline)" decision={data.baseline} />
            <DecisionColumn title="After (disturbed)" decision={data.disturbed} />
          </div>

          <Card size="sm">
            <CardHeader>
              <CardTitle className="text-sm">Applied parameters</CardTitle>
            </CardHeader>
            <CardContent>
              <ul className="space-y-1 text-sm" data-testid="scenario-params">
                {data.parameters.map(p => (
                  <li key={p.name}>
                    {p.name}: {p.before} → <strong>{p.after}</strong>
                  </li>
                ))}
              </ul>
            </CardContent>
          </Card>

          <Table data-testid="scenario-deltas">
            <TableHeader>
              <TableRow>
                <TableHead>Metric</TableHead>
                <TableHead className="text-right">Before</TableHead>
                <TableHead className="text-right">After</TableHead>
                <TableHead className="text-right">Change</TableHead>
              </TableRow>
            </TableHeader>
            <TableBody>
              {data.comparison.deltas.map(d => (
                <TableRow key={d.metric}>
                  <TableCell>
                    {d.label} <span className="text-muted-foreground">({d.unit})</span>
                  </TableCell>
                  <TableCell className="text-right">{fmt(d.baseline)}</TableCell>
                  <TableCell className="text-right">{fmt(d.disturbed)}</TableCell>
                  <TableCell className="text-right">
                    {d.change > 0 ? '+' : ''}
                    {fmt(d.change)}
                  </TableCell>
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>
      )}
    </section>
  );
}
