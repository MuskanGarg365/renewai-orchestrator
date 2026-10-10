import { useSyncExternalStore } from 'react';
import {
  DEMO_CONTROLS_ENABLED,
  isOutageSimulated,
  setOutageSimulated,
  subscribeDemoControls,
} from '@/lib/demoControls';

export function DemoControls() {
  const outage = useSyncExternalStore(
    subscribeDemoControls,
    isOutageSimulated,
    isOutageSimulated
  );

  if (!DEMO_CONTROLS_ENABLED) return null;

  return (
    <label
      className="flex items-center gap-2 rounded-md border border-dashed px-2 py-1 text-xs"
      data-testid="demo-controls"
    >
      <input
        type="checkbox"
        checked={outage}
        onChange={e => setOutageSimulated(e.target.checked)}
      />
      Demo: simulate service outage
    </label>
  );
}
