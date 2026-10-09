const nf = new Intl.NumberFormat('en-IN', { maximumFractionDigits: 1 });

export const fmt = (value: number | null | undefined, unit = ''): string =>
  value == null ? '—' : `${nf.format(value)}${unit ? ' ' + unit : ''}`;

export const fmtPrice = (value: number | null | undefined): string =>
  value == null ? '—' : `₹${nf.format(value)}/MWh`;

export const fmtTime = (iso: string | null | undefined): string =>
  iso
    ? new Date(iso).toLocaleString('en-IN', {
        timeZone: 'Asia/Kolkata',
        day: '2-digit',
        month: 'short',
        hour: '2-digit',
        minute: '2-digit',
      }) + ' IST'
    : '—';