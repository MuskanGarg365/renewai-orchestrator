import { useEffect } from 'react';

declare global {
  interface Window {
    embeddedservice_bootstrap?: {
      settings: Record<string, unknown>;
      init: (
        orgId: string,
        deployment: string,
        siteUrl: string,
        options: { scrt2URL: string }
      ) => void;
    };
  }
}

const env = import.meta.env;

/** Loads Salesforce's chat widget so the Agentforce agent appears as a chat button. */
export function AgentChat() {
  useEffect(() => {
    const bootstrapUrl = env.VITE_AGENT_BOOTSTRAP_URL;
    if (!bootstrapUrl || !env.VITE_AGENT_ORG_ID) return; // not configured: render nothing
    if (document.getElementById('renewai-agent-script')) return;

    const script = document.createElement('script');
    script.id = 'renewai-agent-script';
    script.src = bootstrapUrl;
    script.async = true;
    script.onload = () => {
      try {
        window.embeddedservice_bootstrap!.settings.language = 'en_US';
        window.embeddedservice_bootstrap!.init(
          env.VITE_AGENT_ORG_ID,
          env.VITE_AGENT_DEPLOYMENT,
          env.VITE_AGENT_SITE_URL,
          { scrt2URL: env.VITE_AGENT_SCRT_URL }
        );
      } catch (err) {
        console.error('Agent chat failed to start', err);
      }
    };
    script.onerror = () => console.error('Agent chat script could not load');
    document.body.appendChild(script);
  }, []);

  return null;
}