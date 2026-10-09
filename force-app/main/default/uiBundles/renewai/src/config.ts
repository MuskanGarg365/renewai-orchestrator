export type DataMode = 'live' | 'fixture';

const env = import.meta.env;

export const DATA_MODE: DataMode =
  env.VITE_DATA_MODE === 'fixture' ? 'fixture' : 'live';

export const APEX_BASE_PATH: string =
  env.VITE_APEX_BASE_PATH ?? '/services/apexrest/renewai/v1';

export const DEFAULT_AS_OF = '2026-10-09T06:30:00Z';

export const MAX_AGE_MINUTES = 30;
export const INTERVAL_MINUTES = 15;

export function resolveAsOf(): string {
  const configured: string = env.VITE_AS_OF ?? DEFAULT_AS_OF;
  if (configured !== 'now') return configured;

  const ms = 15 * 60 * 1000;
  const rounded = new Date(Math.floor(Date.now() / ms) * ms);
  return rounded.toISOString().replace('.000Z', 'Z');
}