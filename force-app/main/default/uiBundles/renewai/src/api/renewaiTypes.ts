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
/* ---------------- Day 5: decision engine ---------------- */

export type ObjectiveMode =
  | 'Balanced'
  | 'Cost First'
  | 'Clean Energy First'
  | 'Reliability First';

export const OBJECTIVE_MODES: ObjectiveMode[] = [
  'Balanced',
  'Cost First',
  'Clean Energy First',
  'Reliability First',
];

export type ActionType =
  | 'Charge'
  | 'Discharge'
  | 'Buy'
  | 'Sell'
  | 'Reserve'
  | 'Curtail';

export interface ActionLine {
  actionType: ActionType;
  assetCode: string;
  quantityMW: number;
}

export interface TermScore {
  term: string;
  rawValue: number;
  normalized: number;
  weight: number;
  contribution: number;
}

export interface CandidateResult {
  candidateId: string;
  label: string;
  feasible: boolean;
  score: number | null;
  rank: number | null;
  actions: ActionLine[];
  rejectionReasons: string[];
  breakdown: TermScore[];
}

export interface DecisionInputs {
  renewableMW: number;
  demandMW: number;
  demandGapMW: number;
  energyPriceMWh: number;
}

export interface DecisionResponse {
  success: true;
  correlationId: string;
  decisionId: string;
  asOf: string;
  objectiveMode: ObjectiveMode;
  confidence: number;
  reserveMW: number;
  approvalStatus: 'Not Required' | 'Pending' | 'Approved';
  explanation: string;
  inputs: DecisionInputs;
  selected: CandidateResult;
  alternatives: CandidateResult[];
  rejected: CandidateResult[];
}

// ---------------- Day 6: scenarios ----------------

export const SCENARIO_TYPES = [
  'Cloud Front',
  'Price Spike',
  'Demand Surge',
  'Battery Outage',
] as const;
export type ScenarioType = (typeof SCENARIO_TYPES)[number];

export interface ParamChange {
  name: string;
  before: string;
  after: string;
}

export interface MetricDelta {
  metric: string;
  label: string;
  unit: string;
  baseline: number;
  disturbed: number;
  change: number;
}

export interface ScenarioComparison {
  decisionChanged: boolean;
  baselineLabel: string;
  disturbedLabel: string;
  deltas: MetricDelta[];
}

export interface ScenarioResponse {
  success: true;
  correlationId: string;
  scenarioId: string;
  scenarioType: ScenarioType;
  description: string;
  objectiveMode: ObjectiveMode;
  asOf: string;
  status: string;
  parameters: ParamChange[];
  baseline: DecisionResponse;
  disturbed: DecisionResponse;
  comparison: ScenarioComparison;
}

// ---------------- Day 8: two-hour simulation ----------------

export interface BatteryPoint {
  assetCode: string;
  socPercent: number;
  available: boolean;
}

export interface SimStep {
  stepIndex: number;
  timestamp: string;
  intensity: number;
  renewableMW: number;
  demandMW: number;
  priceMWh: number;
  confidencePct: number;
  reserveMW: number;
  clusterId: string;
  clusterLabel: string;
  setpoints: string;
  approvalStatus: 'Not Required' | 'Pending' | 'Approved';
  reliabilityEvent: boolean;
  dischargeMW: number;
  chargeMW: number;
  buyMW: number;
  sellMW: number;
  curtailMW: number;
  energyCostINR: number;
  revenueINR: number;
  carbonT: number;
  curtailedMWh: number;
  cumEnergyCostINR: number;
  cumRevenueINR: number;
  cumCarbonT: number;
  cumCurtailedMWh: number;
  cumReliabilityEvents: number;
  batteries: BatteryPoint[];
  decisionId?: string;
}

export interface SimTotals {
  energyCostINR: number;
  revenueINR: number;
  netCostINR: number;
  carbonT: number;
  curtailedMWh: number;
  reliabilityEvents: number;
  pendingApprovals: number;
  clusterChanges: number;
}

export interface SimRun {
  objectiveMode: ObjectiveMode;
  checksum: string;
  totals: SimTotals;
  steps: SimStep[];
}

export interface SimulationResponse {
  success: true;
  correlationId: string;
  scenarioId: string;
  scenarioType: ScenarioType;
  description: string;
  status: string;
  asOf: string;
  intervalMinutes: number;
  objectiveMode: ObjectiveMode;
  intensityProfile: number[];
  primary: SimRun;
  comparison: SimRun[];
}

export interface SimulationCancelResponse {
  success: true;
  correlationId: string;
  scenarioId: string;
  status: string;
}
