import type { PortfolioResponse } from '@/api/renewaiTypes';
import type { DataMode } from '@/config';
import { StatusAlert } from '@/components/alerts/status-alert';
import { fmtTime } from './format';

export function DataQualityBanner({
  data,
  mode,
}: {
  data: PortfolioResponse;
  mode: DataMode;
}) {
  const staleCount = data.assets.filter(a => a.stale === true).length;
  const missing = data.assets.filter(
    a =>
      (a.assetType === 'Solar' || a.assetType === 'Wind') &&
      a.snapshotTimestamp == null
  ).length;

  return (
    <div className="space-y-2" data-testid="data-quality">
      {mode === 'fixture' && (
        <StatusAlert variant="info">
          Fixture mode: showing bundled synthetic data, not live Salesforce data.
        </StatusAlert>
      )}
      {staleCount > 0 || missing > 0 ? (
        <StatusAlert variant="error">
          Data quality warning: {staleCount} stale and {missing} missing asset
          snapshots as of {fmtTime(data.asOf)}.
        </StatusAlert>
      ) : (
        <StatusAlert variant="success">
          Data quality OK: all snapshots are fresh as of {fmtTime(data.asOf)}.
          Synthetic data.
        </StatusAlert>
      )}
    </div>
  );
}