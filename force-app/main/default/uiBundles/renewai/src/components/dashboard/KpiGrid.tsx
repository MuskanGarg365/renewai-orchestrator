import type { PortfolioMetrics, AssetSummary } from '@/api/renewaiTypes';
import { KpiCard } from './kpiCard';
import { fmt, fmtPrice } from './format';

export function sumGeneration(
  assets: AssetSummary[],
  type: 'Solar' | 'Wind'
): number {
  return assets
    .filter(a => a.assetType === type)
    .reduce((total, a) => total + (a.generationMW ?? 0), 0);
}

interface Props {
  metrics: PortfolioMetrics;
  assets: AssetSummary[];
}

export function KpiGrid({ metrics, assets }: Props) {
  const gap = metrics.demandGapMW;
  return (
    <section
      aria-label="Portfolio KPIs"
      className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6"
    >
      <KpiCard label="Solar" value={fmt(sumGeneration(assets, 'Solar'), 'MW')} />
      <KpiCard label="Wind" value={fmt(sumGeneration(assets, 'Wind'), 'MW')} />
      <KpiCard label="Demand" value={fmt(metrics.totalDemandMW, 'MW')} />
      <KpiCard
        label="Demand gap"
        value={fmt(gap, 'MW')}
        tone={gap > 0 ? 'warn' : 'default'}
        hint={gap > 0 ? 'Demand exceeds renewables' : 'Renewables cover demand'}
      />
      <KpiCard label="Price" value={fmtPrice(metrics.energyPriceMWh)} />
      <KpiCard
        label="Grid headroom"
        value={fmt(metrics.gridHeadroomMW, 'MW')}
        hint={`of ${fmt(metrics.gridCapacityMW, 'MW')}`}
      />
    </section>
  );
}