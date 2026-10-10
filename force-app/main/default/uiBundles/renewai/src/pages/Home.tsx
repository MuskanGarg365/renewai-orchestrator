// export default function Home() {
//   return (
//     <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-12">
//       <div className="text-center">
//         <h1 className="text-4xl font-bold text-gray-900 mb-4">Home</h1>
//         <p className="text-lg text-gray-600 mb-8">
//           Welcome to your React application.
//         </p>
//       </div>
//     </div>
//   );
// }


import { DATA_MODE } from '@/config';
import { usePortfolio } from '@/hooks/usePortfolio';
import { Badge } from '@/components/ui/badge';
import { Button } from '@/components/ui/button';
import { AssetTable } from '@/components/dashboard/AssetTable';
import { BatteryCards } from '@/components/dashboard/BatteryCards';
import { DataQualityBanner } from '@/components/dashboard/DataQualityBanner';
import { KpiGrid } from '@/components/dashboard/KpiGrid';
import { DecisionPanel } from '@/components/decision/DecisionPanel';
import { ScenarioPanel } from '@/components/scenario/ScenarioPanel';
import {
  EmptyView,
  ErrorView,
  LoadingView,
} from '@/components/dashboard/stateViews';
import { fmtTime } from '@/components/dashboard/format';

export default function Home() {
  const { status, data, error, refreshing, reload } = usePortfolio(DATA_MODE);

  return (
    <div className="mx-auto max-w-7xl space-y-6 px-4 py-8 sm:px-6 lg:px-8">
      <header className="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h1 className="text-2xl font-bold">Portfolio overview</h1>
          <p className="text-muted-foreground text-sm">
            {data ? `As of ${fmtTime(data.asOf)} · ` : ''}
            Correlation ID: {data?.correlationId ?? '—'}
          </p>
        </div>
        <div className="flex items-center gap-2">
          <Badge variant={DATA_MODE === 'live' ? 'default' : 'outline'}>
            {DATA_MODE === 'live' ? 'Live' : 'Fixture'}
          </Badge>
          <Button variant="outline" onClick={reload} disabled={refreshing}>
            {refreshing ? 'Refreshing…' : 'Refresh'}
          </Button>
        </div>
      </header>

      {status === 'loading' && <LoadingView />}
      {status === 'error' && error && <ErrorView error={error} onRetry={reload} />}
      {status === 'empty' && <EmptyView onRetry={reload} />}
      {status === 'ready' && data && (
        <>
          <DataQualityBanner data={data} mode={DATA_MODE} />
          <KpiGrid metrics={data.metrics} assets={data.assets} />
          <BatteryCards assets={data.assets} />
          <DecisionPanel />
          <ScenarioPanel />
          <AssetTable assets={data.assets} />
        </>
      )}
    </div>
  );
}