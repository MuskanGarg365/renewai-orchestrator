import type { RenewAIApiError } from '@/api/renewaiClient';
import { Button } from '@/components/ui/button';
import { Skeleton } from '@/components/ui/skeleton';
import { StatusAlert } from '@/components/alerts/status-alert';

export function LoadingView() {
  return (
    <div className="space-y-4" role="status" aria-label="Loading portfolio">
      <div className="grid grid-cols-2 gap-3 md:grid-cols-3 lg:grid-cols-6">
        {Array.from({ length: 6 }, (_, i) => (
          <Skeleton key={i} className="h-24" />
        ))}
      </div>
      <Skeleton className="h-24" />
      <Skeleton className="h-64" />
    </div>
  );
}

export function EmptyView({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="space-y-3" data-testid="empty-view">
      <StatusAlert variant="info">
        No active assets were returned. Run RenewAISeedData.loadAll() in the
        org, then reload.
      </StatusAlert>
      <Button onClick={onRetry}>Reload</Button>
    </div>
  );
}

const messages: Record<RenewAIApiError['kind'], string> = {
  session:
    'Your Salesforce session is not valid. Re-authenticate (sf org login web) and restart the dev server, or sign in again.',
  forbidden:
    'You are signed in but cannot read RenewAI data. Check the RenewAI_Operator permission set and Apex class access.',
  validation: 'The request was rejected by validation.',
  not_found:
    'The RenewAI API endpoint was not found. Has the Apex class been deployed?',
  server: 'RenewAI could not process the request.',
  network: 'Could not reach Salesforce. Check your connection.',
};

export function ErrorView({
  error,
  onRetry,
}: {
  error: RenewAIApiError;
  onRetry: () => void;
}) {
  return (
    <div className="space-y-3" data-testid="error-view">
      <StatusAlert variant="error">
        {messages[error.kind]} {error.message}
        {error.correlationId ? ` (Correlation ID: ${error.correlationId})` : ''}
      </StatusAlert>
      <Button onClick={onRetry}>Retry</Button>
    </div>
  );
}