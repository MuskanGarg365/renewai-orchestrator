import type { ObjectiveMode, ScenarioType } from './renewaiTypes';

export interface ScenarioInfo {
  type: ScenarioType;
  title: string;
  description: string;
  /** Fixed, scripted parameters shown as a preview before running. */
  preview: string[];
  /** Objective that shows the scenario most clearly (matches Apex). */
  defaultMode: ObjectiveMode;
}

// Keep in sync with RenewAIScenarioCatalog.cls. The numbers the engine
// actually used come back in the response (parameters).
export const SCENARIOS: ScenarioInfo[] = [
  {
    type: 'Cloud Front',
    title: 'Cloud Front',
    description: 'Solar output drops and the forecast becomes less certain.',
    preview: ['Solar output −40%', 'Forecast confidence −0.30'],
    defaultMode: 'Balanced',
  },
  {
    type: 'Price Spike',
    title: 'Price Spike',
    description: 'The market price jumps.',
    preview: ['Energy price +80%'],
    defaultMode: 'Cost First',
  },
  {
    type: 'Demand Surge',
    title: 'Demand Surge',
    description: 'Industrial demand rises above forecast.',
    preview: ['Demand +15%'],
    defaultMode: 'Balanced',
  },
  {
    type: 'Battery Outage',
    title: 'Battery Outage',
    description: 'One battery unit goes offline.',
    preview: ['First available battery unit offline'],
    defaultMode: 'Cost First',
  },
];

export function scenarioInfo(type: ScenarioType): ScenarioInfo {
  return SCENARIOS.find(s => s.type === type) ?? SCENARIOS[0];
}
