import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';

interface KpiCardProps {
  label: string;
  value: string;
  hint?: string;
  tone?: 'default' | 'warn';
}

export function KpiCard({ label, value, hint, tone = 'default' }: KpiCardProps) {
  return (
    <Card size="sm" data-testid={`kpi-${label.toLowerCase().replace(/\s+/g, '-')}`}>
      <CardHeader>
        <CardTitle className="text-muted-foreground text-xs font-medium uppercase tracking-wide">
          {label}
        </CardTitle>
      </CardHeader>
      <CardContent>
        <div
          className={`text-2xl font-semibold ${tone === 'warn' ? 'text-amber-600' : ''}`}
        >
          {value}
        </div>
        {hint && <p className="text-muted-foreground mt-1 text-xs">{hint}</p>}
      </CardContent>
    </Card>
  );
}