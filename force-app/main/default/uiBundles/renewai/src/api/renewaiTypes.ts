export interface AssetSummary {
  assetCode: string;
  assetName: string;
  assetType: 'Solar' | 'Wind' | 'Battery' | 'Industrial Demand' | 'Grid';
  capacityMW: number | null;
  generationMW: number | null;
  demandMW: number | null;
  stateOfChargePercent: number | null;
  availableEnergyMWh: number | null;
  snapshotTimestamp: string | null;
  status: string | null;
  stale: boolean | null;
}

export interface PortfolioMetrics {
  renewableTotalMW: number;
  totalDemandMW: number;
  demandGapMW: number;
  availableBatteryEnergyMWh: number;
  gridCapacityMW: number;
  gridHeadroomMW: number;
  energyPriceMWh?: number | null;
  priceTimestamp?: string | null;
}

export interface PortfolioResponse {
  success: true;
  correlationId: string;
  asOf: string;
  intervalMinutes: number;
  metrics: PortfolioMetrics;
  assets: AssetSummary[];
}

export interface ApiErrorDetail {
  field: string;
  code: string;
  message: string;
}

export interface ErrorResponse {
  success: false;
  correlationId: string;
  errorCode: string;
  message: string;
  errors: ApiErrorDetail[];
}