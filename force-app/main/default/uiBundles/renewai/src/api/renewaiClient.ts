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
  DecisionResponse,
  ErrorResponse,
  ObjectiveMode,
  PortfolioResponse,
  ScenarioResponse,
  ScenarioType,
} from './renewaiTypes';
import portfolioFixture from './fixtures/portfolio.json';
import decisionFixtures from './fixtures/decisions.json';
import scenarioFixtures from './fixtures/scenarios.json';

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
  if (mode === 'fixture') {
    await new Promise(resolve => setTimeout(resolve, 250));
    const fixtures = decisionFixtures as unknown as Record<
      ObjectiveMode,
      DecisionResponse
    >;
    return fixtures[objectiveMode];
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
