import type { TermScore } from '@/api/renewaiTypes';

const LABELS: Record<string, string> = {
  cost: 'Cost',
  carbon: 'Carbon',
  curtailment: 'Curtailment',
  degradation: 'Battery wear',
  reliability: 'Reliability risk',
  profit: 'Lost profit',
};

/** Lower is better. Each bar is that term's weighted contribution to the score. */
export function ScoreBreakdown({ terms }: { terms: TermScore[] }) {
  const max = Math.max(0.0001, ...terms.map(t => t.weight));

  return (
    <div className="space-y-2" data-testid="score-breakdown">
      {terms.map(t => (
        <div key={t.term} className="text-xs">
          <div className="mb-0.5 flex justify-between">
            <span>
              {LABELS[t.term] ?? t.term}{' '}
              <span className="text-muted-foreground">
                (weight {Math.round(t.weight * 100)}%)
              </span>
            </span>
            <span className="font-medium">{t.contribution.toFixed(3)}</span>
          </div>
          <div
            className="bg-muted h-1.5 overflow-hidden rounded-full"
            role="progressbar"
            aria-label={`${LABELS[t.term] ?? t.term} contribution`}
            aria-valuenow={t.contribution}
            aria-valuemin={0}
            aria-valuemax={max}
          >
            <div
              className="bg-primary h-full"
              style={{ width: `${Math.min((t.contribution / max) * 100, 100)}%` }}
            />
          </div>
        </div>
      ))}
    </div>
  );
}
