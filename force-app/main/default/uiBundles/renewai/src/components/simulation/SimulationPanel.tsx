import { useState } from 'react';
import { DATA_MODE } from '@/config';
import { useSimulation } from '@/hooks/useSimulation';
import { SCENARIOS, scenarioInfo } from '@/api/scenarios';
import {
  OBJECTIVE_MODES,
  type ObjectiveMode,
  type ScenarioType,
  type SimTotals,
} from '@/api/renewaiTypes';
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

const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000;

function istTime(iso: string): string {
  const t = new Date(new Date(iso).getTime() + IST_OFFSET_MS);
  return `${String(t.getUTCHours()).padStart(2, '0')}:${String(
    t.getUTCMinutes()
  ).padStart(2, '0')}`;
}

function fmt(n: number, digits = 2): string {
  return n.toLocaleString('en-IN', { maximumFractionDigits: digits });
}

function inr(n: number): string {
  return `₹${n.toLocaleString('en-IN', { maximumFractionDigits: 0 })}`;
}

function Kpi({
  label,
  value,
  testId,
}: {
  label: string;
  value: string;
  testId?: string;
}) {
  return (
    <Card size="sm">
      <CardContent className="space-y-1">
        <p className="text-muted-foreground text-xs">{label}</p>
        <p className="text-lg font-semibold" data-testid={testId}>
          {value}
        </p>
      </CardContent>
    </Card>
  );
}

function TotalsKpis({ totals }: { totals: SimTotals }) {
  return (
    <div className="grid grid-cols-2 gap-3 md:grid-cols-4 lg:grid-cols-6">
      <Kpi label="Energy bought" value={inr(totals.energyCostINR)} testId="kpi-cost" />
      <Kpi label="Energy sold" value={inr(totals.revenueINR)} />
      <Kpi label="Net cost" value={inr(totals.netCostINR)} />
      <Kpi label="Carbon proxy (t CO₂)" value={fmt(totals.carbonT)} />
      <Kpi label="Curtailed (MWh)" value={fmt(totals.curtailedMWh)} />
      <Kpi
        label="Reliability events"
        value={String(totals.reliabilityEvents)}
        testId="kpi-reliability"
      />
    </div>
  );
}

export function SimulationPanel() {
  const [scenario, setScenario] = useState<ScenarioType>('Cloud Front');
  const [objective, setObjective] = useState<ObjectiveMode>('Balanced');
  const { status, data, error, run, cancel } = useSimulation(DATA_MODE);

  function pick(type: ScenarioType) {
    setScenario(type);
    setObjective(scenarioInfo(type).defaultMode);
  }

  return (
    <section aria-label="Two-hour simulation" className="space-y-4">
      <div>
        <h2 className="text-lg font-semibold">Two-hour simulation</h2>
        <p className="text-muted-foreground text-sm">
          Plays a scenario across eight 15-minute intervals. The engine decides
          at every step, batteries carry their charge forward, and the KPIs add
          up. Same inputs always give the same checksum.
        </p>
      </div>

      <Card size="sm">
        <CardContent className="flex flex-wrap items-end justify-between gap-3">
          <div className="flex flex-wrap items-end gap-3">
            <div className="space-y-1">
              <label className="text-sm" htmlFor="sim-scenario">
                Scenario
              </label>
              <select
                id="sim-scenario"
                className="border-input bg-background h-9 rounded-md border px-2 text-sm"
                value={scenario}
                onChange={e => pick(e.target.value as ScenarioType)}
              >
                {SCENARIOS.map(s => (
                  <option key={s.type} value={s.type}>
                    {s.title}
                  </option>
                ))}
              </select>
            </div>
            <div className="space-y-1">
              <label className="text-sm" htmlFor="sim-objective">
                Objective
              </label>
              <select
                id="sim-objective"
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
            </div>
          </div>
          <div className="flex gap-2">
            <Button
              onClick={() => run(scenario, objective)}
              disabled={status === 'running'}
            >
              {status === 'running' ? 'Simulating…' : 'Run simulation'}
            </Button>
            {status === 'running' && (
              <Button variant="outline" onClick={() => cancel()}>
                Cancel
              </Button>
            )}
          </div>
        </CardContent>
      </Card>

      {status === 'cancelled' && (
        <StatusAlert variant="info">
          {data
            ? 'This run was discarded and marked Cancelled in Salesforce.'
            : 'Cancelled. Any run that had already started on the server stays saved as Completed.'}
        </StatusAlert>
      )}

      {status === 'error' && error && (
        <StatusAlert variant="error">
          {error.message}
          {error.correlationId ? ` (Correlation ID: ${error.correlationId})` : ''}
        </StatusAlert>
      )}

      {(status === 'done' || (status === 'cancelled' && data)) && data && (
        <div className="space-y-4" data-testid="simulation-result">
          <div className="flex flex-wrap items-center gap-2">
            <Badge variant="secondary">{data.scenarioType}</Badge>
            <Badge variant="outline">{data.primary.objectiveMode}</Badge>
            <Badge variant="outline" data-testid="sim-checksum">
              Checksum {data.primary.checksum}
            </Badge>
            <span className="text-muted-foreground text-xs">
              Correlation ID: {data.correlationId} · Scenario: {data.scenarioId}
            </span>
            {status === 'done' && (
              <Button size="sm" variant="outline" onClick={() => cancel()}>
                Discard run
              </Button>
            )}
          </div>

          <TotalsKpis totals={data.primary.totals} />

          <div>
            <h3 className="mb-2 text-sm font-semibold">Timeline</h3>
            <div className="overflow-x-auto">
              <Table data-testid="sim-timeline">
                <TableHeader>
                  <TableRow>
                    <TableHead>Step</TableHead>
                    <TableHead>IST</TableHead>
                    <TableHead className="text-right">Disturbance</TableHead>
                    <TableHead className="text-right">Renewable MW</TableHead>
                    <TableHead className="text-right">Demand MW</TableHead>
                    <TableHead className="text-right">Price</TableHead>
                    <TableHead className="text-right">Confidence</TableHead>
                    <TableHead>Action cluster</TableHead>
                    <TableHead>Setpoints</TableHead>
                    <TableHead>Approval</TableHead>
                    <TableHead>Battery charge</TableHead>
                    <TableHead className="text-right">Cum. cost</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.primary.steps.map(s => (
                    <TableRow key={s.stepIndex}>
                      <TableCell>{s.stepIndex + 1}</TableCell>
                      <TableCell>{istTime(s.timestamp)}</TableCell>
                      <TableCell className="text-right">
                        {Math.round(s.intensity * 100)}%
                      </TableCell>
                      <TableCell className="text-right">{fmt(s.renewableMW)}</TableCell>
                      <TableCell className="text-right">{fmt(s.demandMW)}</TableCell>
                      <TableCell className="text-right">{fmt(s.priceMWh)}</TableCell>
                      <TableCell className="text-right">{fmt(s.confidencePct, 0)}%</TableCell>
                      <TableCell>
                        {s.clusterLabel}
                        {s.reliabilityEvent && (
                          <Badge variant="destructive" className="ml-2">
                            Reliability event
                          </Badge>
                        )}
                      </TableCell>
                      <TableCell className="text-muted-foreground text-xs">
                        {s.setpoints}
                      </TableCell>
                      <TableCell>
                        {s.approvalStatus === 'Pending' ? 'Required' : '—'}
                      </TableCell>
                      <TableCell className="text-xs">
                        {s.batteries
                          .map(
                            b =>
                              `${b.assetCode.slice(-2)}: ${fmt(b.socPercent, 1)}%${
                                b.available ? '' : ' (offline)'
                              }`
                          )
                          .join(' · ')}
                      </TableCell>
                      <TableCell className="text-right">{inr(s.cumEnergyCostINR)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          </div>

          {data.comparison.length > 0 && (
            <div>
              <h3 className="mb-2 text-sm font-semibold">
                Objective comparison (same {data.scenarioType} scenario)
              </h3>
              <div className="overflow-x-auto">
                <Table data-testid="sim-comparison">
                  <TableHeader>
                    <TableRow>
                      <TableHead>Objective</TableHead>
                      <TableHead className="text-right">Net cost</TableHead>
                      <TableHead className="text-right">Carbon (t)</TableHead>
                      <TableHead className="text-right">Curtailed (MWh)</TableHead>
                      <TableHead className="text-right">Reliability events</TableHead>
                      <TableHead className="text-right">Approvals needed</TableHead>
                      <TableHead className="text-right">Cluster changes</TableHead>
                    </TableRow>
                  </TableHeader>
                  <TableBody>
                    {data.comparison.map(r => (
                      <TableRow
                        key={r.objectiveMode}
                        data-selected={r.objectiveMode === data.primary.objectiveMode}
                      >
                        <TableCell>
                          {r.objectiveMode}
                          {r.objectiveMode === data.primary.objectiveMode && (
                            <Badge variant="secondary" className="ml-2">
                              Selected
                            </Badge>
                          )}
                        </TableCell>
                        <TableCell className="text-right">{inr(r.totals.netCostINR)}</TableCell>
                        <TableCell className="text-right">{fmt(r.totals.carbonT)}</TableCell>
                        <TableCell className="text-right">{fmt(r.totals.curtailedMWh)}</TableCell>
                        <TableCell className="text-right">{r.totals.reliabilityEvents}</TableCell>
                        <TableCell className="text-right">{r.totals.pendingApprovals}</TableCell>
                        <TableCell className="text-right">{r.totals.clusterChanges}</TableCell>
                      </TableRow>
                    ))}
                  </TableBody>
                </Table>
              </div>
              <p className="text-muted-foreground mt-2 text-xs">
                Net cost = energy bought minus energy sold. Negative means a net
                gain. Carbon proxy counts grid purchases only (0.82 t per MWh).
                A reliability event is a step where the plan leaves at least 30%
                of the reserve target unmet. All figures are synthetic.
              </p>
            </div>
          )}
        </div>
      )}
    </section>
  );
}
