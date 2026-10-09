import type { AssetSummary } from '@/api/renewaiTypes';
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
import { fmt } from './format';

export function BatteryCards({ assets }: { assets: AssetSummary[] }) {
  const batteries = assets.filter(a => a.assetType === 'Battery');
  if (batteries.length === 0) return null;

  return (
    <section aria-label="Battery state of charge" className="grid gap-3 md:grid-cols-2">
      {batteries.map(b => {
        const soc = b.stateOfChargePercent;
        const low = soc != null && soc < 20;
        return (
          <Card size="sm" key={b.assetCode} data-testid={`battery-${b.assetCode}`}>
            <CardHeader>
              <CardTitle className="text-sm">{b.assetName}</CardTitle>
            </CardHeader>
            <CardContent>
              <div className="flex items-baseline justify-between">
                <span className="text-2xl font-semibold">
                  {soc == null ? '—' : `${soc.toFixed(0)}%`}
                </span>
                <span className="text-muted-foreground text-xs">
                  {fmt(b.availableEnergyMWh, 'MWh')} available
                </span>
              </div>
              <div
                className="bg-muted mt-2 h-2 overflow-hidden rounded-full"
                role="progressbar"
                aria-valuenow={soc ?? 0}
                aria-valuemin={0}
                aria-valuemax={100}
                aria-label={`${b.assetName} state of charge`}
              >
                <div
                  className={`h-full ${low ? 'bg-amber-500' : 'bg-emerald-500'}`}
                  style={{ width: `${Math.min(Math.max(soc ?? 0, 0), 100)}%` }}
                />
              </div>
            </CardContent>
          </Card>
        );
      })}
    </section>
  );
}