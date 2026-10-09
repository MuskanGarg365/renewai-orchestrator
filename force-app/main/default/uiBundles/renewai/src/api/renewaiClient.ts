import { createDataSDK } from '@salesforce/platform-sdk';
import {
  APEX_BASE_PATH,
  DATA_MODE,
  INTERVAL_MINUTES,
  MAX_AGE_MINUTES,
  resolveAsOf,
  type DataMode,
} from '@/config';
import type { ErrorResponse, PortfolioResponse } from './renewaiTypes';
import portfolioFixture from './fixtures/portfolio.json';

export type ApiErrorKind =
  | 'unauthorized'
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
  if (status === 401 || status === 403) return 'unauthorized';
  if (status === 400) return 'validation';
  if (status === 404) return 'not_found';
  return 'server';
}

async function request<T>(path: string): Promise<T> {
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
      headers: { Accept: 'application/json' },
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
    const err = body as Partial<ErrorResponse> | null;
    throw new RenewAIApiError(
      err?.message ?? `Request failed (${response.status}).`,
      kindForStatus(response.status),
      response.status,
      err?.correlationId ?? correlationId
    );
  }
  if (body == null) {
    throw new RenewAIApiError(
      'Unexpected response from Salesforce.',
      'unauthorized',
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