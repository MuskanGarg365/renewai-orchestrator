import type { AssetSummary } from '@/api/renewaiTypes';
import { Badge } from '@/components/ui/badge';
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table';
import { fmt } from './format';

export function AssetTable({ assets }: { assets: AssetSummary[] }) {
  return (
    <section aria-label="Asset availability">
      <h2 className="mb-2 text-sm font-semibold">Assets</h2>
      <Table>
        <TableHeader>
          <TableRow>
            <TableHead>Asset</TableHead>
            <TableHead>Type</TableHead>
            <TableHead className="text-right">Capacity</TableHead>
            <TableHead className="text-right">Output / demand</TableHead>
            <TableHead>Status</TableHead>
            <TableHead>Data</TableHead>
          </TableRow>
        </TableHeader>
        <TableBody>
          {assets.map(a => {
            const active = a.status === 'Active';
            const value =
              a.assetType === 'Industrial Demand'
                ? a.demandMW
                : a.assetType === 'Battery' || a.assetType === 'Grid'
                  ? null
                  : a.generationMW;
            return (
              <TableRow key={a.assetCode}>
                <TableCell className="font-medium">{a.assetName}</TableCell>
                <TableCell>{a.assetType}</TableCell>
                <TableCell className="text-right">{fmt(a.capacityMW, 'MW')}</TableCell>
                <TableCell className="text-right">{fmt(value, 'MW')}</TableCell>
                <TableCell>
                  <Badge variant={active ? 'secondary' : 'destructive'}>
                    {a.status ?? 'Unknown'}
                  </Badge>
                </TableCell>
                <TableCell>
                  {a.stale === true ? (
                    <Badge variant="destructive">Stale</Badge>
                  ) : a.stale === false ? (
                    <Badge variant="outline">Fresh</Badge>
                  ) : (
                    <span className="text-muted-foreground">—</span>
                  )}
                </TableCell>
              </TableRow>
            );
          })}
        </TableBody>
      </Table>
    </section>
  );
}