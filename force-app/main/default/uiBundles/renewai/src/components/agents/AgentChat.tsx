import { useEffect, useRef } from 'react';
import { embedAgentforceClient } from '@salesforce/agentforce-conversation-client';

export function AgentChat() {
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    // Use the primary Salesforce instance domain URL as the origin
    const salesforceOrigin =
  (import.meta.env.VITE_SF_INSTANCE_URL as string | undefined) ||
  window.location.origin;

    embedAgentforceClient({
      container,
      salesforceOrigin, // Passed explicitly here
      agentforceClientConfig: {
        agentId: '0Xxhg000000lnQHCAY',
        agentLabel: 'Renew_AI_Chat', // Exact API name causing the access/permission block
        renderingConfig: { mode: 'floating' },
      },
    });

    return () => container.replaceChildren();
  }, []);

  return <div ref={containerRef} style={{ minHeight: '500px', width: '100%' }} />;
}
