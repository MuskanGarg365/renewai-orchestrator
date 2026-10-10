import { DATA_MODE } from '@/config';

/**
 * Demo-only switches. They never change business logic; they only let you
 * show on camera what happens when a service call fails.
 */
export const DEMO_CONTROLS_ENABLED: boolean =
  DATA_MODE === 'fixture' || import.meta.env.VITE_DEMO_CONTROLS === 'true';

let outage = false;
const listeners = new Set<() => void>();

export function isOutageSimulated(): boolean {
  return outage;
}

export function setOutageSimulated(value: boolean): void {
  outage = value;
  listeners.forEach(listener => listener());
}

export function subscribeDemoControls(listener: () => void): () => void {
  listeners.add(listener);
  return () => {
    listeners.delete(listener);
  };
}
