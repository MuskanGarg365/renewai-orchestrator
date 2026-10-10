import { createDataSDK } from '@salesforce/platform-sdk';
import {
  APEX_BASE_PATH,
  DATA_MODE,
  INTERVAL_MINUTES,
  MAX_AGE_MINUTES,
  resolveAsOf,
  type DataMode,
} from '@/config';
import type {
  ApprovalOutcome,
  ApprovalResponse,
  ApprovalStatus,
  AuditResponse,
  AuditRow,
  DecisionResponse,
  ErrorResponse,
  ObjectiveMode,
  PortfolioResponse,
  ScenarioResponse,
  ScenarioType,
  SimulationCancelResponse,
  SimulationResponse,
} from './renewaiTypes';
import portfolioFixture from './fixtures/portfolio.json';
import decisionFixtures from './fixtures/decisions.json';
import scenarioFixtures from './fixtures/scenarios.json';
import simulationFixtures from './fixtures/simulations.json';
import { isOutageSimulated } from '@/lib/demoControls';

export type ApiErrorKind =
  | 'session'
  | 'forbidden'
  | 'validation'
  | 'not_found'
  | 'server'
  | 'network';

export class RenewAIApiError extends Error {
  constructor(
    message: string,
    public readonly kind: ApiErrorKind,
    public readonly status?: number,
    public readonly correlationId?: string
  ) {
    super(message);
    this.name = 'RenewAIApiError';
  }
}

function kindForStatus(status: number): ApiErrorKind {
  if (status === 401) return 'session';
  if (status === 403) return 'forbidden';
  if (status === 400) return 'validation';
  if (status === 404) return 'not_found';
  return 'server';
}

/** Demo switch: behaves like a failed Salesforce call, in live and fixture mode. */
function guard(): void {
  if (isOutageSimulated()) {
    throw new RenewAIApiError(
      'Simulated outage: the RenewAI service is unavailable.',
      'network',
      503,
      'RENEWAI-SIMULATED'
    );
  }
}

type PlatformError = { message?: string; errorCode?: string };

async function request<T>(path: string, init?: RequestInit): Promise<T> {
  const sdk = await createDataSDK();
  if (!sdk.fetch) {
    throw new RenewAIApiError(
      'This surface does not support REST calls.',
      'server'
    );
  }

  let response: Response;
  try {
    response = await sdk.fetch(`${APEX_BASE_PATH}${path}`, {
      ...init,
      headers: { Accept: 'application/json', ...(init?.headers ?? {}) },
    });
  } catch {
    throw new RenewAIApiError('Could not reach Salesforce.', 'network');
  }

  const correlationId = response.headers.get('X-Correlation-Id') ?? undefined;
  let body: unknown = null;
  try {
    body = await response.json();
  } catch {
    // non-JSON body (for example a login redirect page)
  }

  if (!response.ok) {
    // RenewAI errors are objects; Salesforce platform errors are arrays.
    const apex = Array.isArray(body)
      ? undefined
      : (body as Partial<ErrorResponse> | null);
    const platform = Array.isArray(body)
      ? ((body as PlatformError[])[0] ?? undefined)
      : undefined;

    const message =
      apex?.message ??
      (platform
        ? `${platform.message ?? ''} [${platform.errorCode ?? ''}]`
        : '');
    const detail = apex?.errors?.[0]
      ? ` (${apex.errors[0].code}: ${apex.errors[0].message})`
      : '';

    throw new RenewAIApiError(
      (message || `Request failed (${response.status}).`) + detail,
      kindForStatus(response.status),
      response.status,
      apex?.correlationId ?? correlationId
    );
  }
  if (body == null) {
    throw new RenewAIApiError(
      'Unexpected response from Salesforce.',
      'session',
      response.status
    );
  }
  return body as T;
}

export async function getPortfolio(
  mode: DataMode = DATA_MODE,
  asOf: string = resolveAsOf()
): Promise<PortfolioResponse> {
  if (mode === 'fixture') {
    // Small delay so loading states are visible and testable.
    await new Promise(resolve => setTimeout(resolve, 150));
    return portfolioFixture as unknown as PortfolioResponse;
  }

  const query = new URLSearchParams({
    asOf,
    intervalMinutes: String(INTERVAL_MINUTES),
    maximumAgeMinutes: String(MAX_AGE_MINUTES),
  });
  return request<PortfolioResponse>(`/portfolio?${query.toString()}`);
}

/** Runs the deterministic decision engine and records the decision in Salesforce. */
export async function runDecision(
  objectiveMode: ObjectiveMode,
  mode: DataMode = DATA_MODE,
  asOf: string = resolveAsOf()
): Promise<DecisionResponse> {
  guard();
  if (mode === 'fixture') {
    await new Promise(resolve => setTimeout(resolve, 250));
    const fixtures = decisionFixtures as unknown as Record<
      ObjectiveMode,
      DecisionResponse
    >;
    return recordFixtureDecision(fixtures[objectiveMode]);
  }

  return request<DecisionResponse>('/decision', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ asOf, objectiveMode }),
  });
}

/** Runs a baseline decision and the same decision after a scripted disturbance. */
export async function runScenario(
  scenarioType: ScenarioType,
  objectiveMode?: ObjectiveMode,
  mode: DataMode = DATA_MODE,
  asOf: string = resolveAsOf()
): Promise<ScenarioResponse> {
  guard();
  if (mode === 'fixture') {
    await new Promise(resolve => setTimeout(resolve, 300));
    const fixtures = scenarioFixtures as unknown as Record<
      ScenarioType,
      ScenarioResponse
    >;
    return fixtures[scenarioType];
  }

  return request<ScenarioResponse>('/scenario', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ asOf, scenarioType, objectiveMode }),
  });
}

/** Runs the eight-interval (two-hour) simulation. Pass a signal to cancel the wait. */
export async function runSimulation(
  scenarioType: ScenarioType,
  objectiveMode?: ObjectiveMode,
  mode: DataMode = DATA_MODE,
  asOf: string = resolveAsOf(),
  signal?: AbortSignal
): Promise<SimulationResponse> {
  guard();
  if (mode === 'fixture') {
    await new Promise(resolve => setTimeout(resolve, 400));
    if (signal?.aborted) throw new RenewAIApiError('Cancelled.', 'network');
    const fixtures = simulationFixtures as unknown as Record<
      ScenarioType,
      SimulationResponse
    >;
    return fixtures[scenarioType];
  }

  return request<SimulationResponse>('/simulation', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ asOf, scenarioType, objectiveMode, compareModes: true }),
    signal,
  });
}

/** Marks a saved simulation as Cancelled in Salesforce. */
export async function cancelSimulation(
  scenarioId: string,
  mode: DataMode = DATA_MODE
): Promise<SimulationCancelResponse> {
  guard();
  if (mode === 'fixture') {
    return {
      success: true,
      correlationId: 'RENEWAI-FIXCANCEL',
      scenarioId,
      status: 'Cancelled',
    };
  }

  return request<SimulationCancelResponse>('/simulation/cancel', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ scenarioId }),
  });
}

// ---------------------------------------------------------------- Day 9

/** In-memory audit trail used in fixture mode so the approval flow works without an org. */
let fixtureAudit: AuditRow[] = [];
let fixtureCounter = 0;

export function resetFixtureAudit(): void {
  fixtureAudit = [];
  fixtureCounter = 0;
}

function recordFixtureDecision(source: DecisionResponse): DecisionResponse {
  fixtureCounter += 1;
  const decisionId = `a0F${String(fixtureCounter).padStart(12, '0')}`;
  const now = new Date().toISOString();
  fixtureAudit.unshift({
    decisionId,
    name: `D-${String(fixtureCounter).padStart(4, '0')}`,
    decisionType: source.selected.label,
    objectiveMode: source.objectiveMode,
    approvalStatus: source.approvalStatus as ApprovalStatus,
    approvalNote: null,
    confidence: Math.round(source.confidence * 10000) / 100,
    score: source.selected.score ?? null,
    snapshotTime: source.asOf,
    correlationId: source.correlationId,
    decidedBy: null,
    decidedOn: null,
    createdDate: now,
    actionCount: source.selected.actions.length,
  });
  return { ...source, decisionId };
}

/** Approves or rejects a Pending decision. Rejecting needs a note. */
export async function approveDecision(
  decisionId: string,
  outcome: ApprovalOutcome,
  note: string,
  mode: DataMode = DATA_MODE
): Promise<ApprovalResponse> {
  guard();
  if (mode === 'fixture') {
    await new Promise(resolve => setTimeout(resolve, 200));
    if (outcome === 'Rejected' && !note.trim()) {
      throw new RenewAIApiError(
        'A note is required when rejecting a decision. (NOTE_REQUIRED)',
        'validation',
        400,
        'RENEWAI-FIXAPPR'
      );
    }
    const row = fixtureAudit.find(r => r.decisionId === decisionId);
    if (!row || row.approvalStatus !== 'Pending') {
      throw new RenewAIApiError(
        'Only decisions that are Pending can be approved or rejected. (NOT_PENDING)',
        'validation',
        400,
        'RENEWAI-FIXAPPR'
      );
    }
    row.approvalStatus = outcome;
    row.approvalNote = note || null;
    row.decidedBy = 'Demo approver';
    row.decidedOn = new Date().toISOString();
    return {
      success: true,
      correlationId: 'RENEWAI-FIXAPPR',
      decisionId,
      approvalStatus: outcome,
      actionsUpdated: row.actionCount,
      decidedBy: row.decidedBy,
      decidedOn: row.decidedOn,
    };
  }

  return request<ApprovalResponse>('/decision/approval', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ decisionId, outcome, note }),
  });
}

/** Most recent decisions with their approval status (the audit trail). */
export async function getAudit(
  status?: ApprovalStatus,
  mode: DataMode = DATA_MODE
): Promise<AuditResponse> {
  guard();
  if (mode === 'fixture') {
    await new Promise(resolve => setTimeout(resolve, 150));
    return {
      success: true,
      correlationId: 'RENEWAI-FIXAUDIT',
      canApprove: true,
      rows: fixtureAudit.filter(r => !status || r.approvalStatus === status),
    };
  }

  const query = new URLSearchParams({ limit: '20' });
  if (status) query.set('status', status);
  return request<AuditResponse>(`/decisions?${query.toString()}`);
}
