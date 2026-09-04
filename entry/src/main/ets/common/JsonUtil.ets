export function errorMessage(e: Object): string {
  const rec = e as Record<string, Object>;
  const code = rec['code'];
  if (code === 2300997) {
    return '本机 HTTP 被系统拦了。请用 Debug 重新安装，确认连的是 http://电脑IP:43180。';
  }
  if (code === 2300007) {
    return '连不上电脑上的服务。确认 server 已启动，手机和电脑同一 Wi-Fi，防火墙放行 43180。';
  }
  if (e instanceof Error) {
    return e.message;
  }
  const msg = rec['message'];
  if (typeof msg === 'string' && msg) {
    return msg;
  }
  return String(e);
}

export function asRecord(value: Object): Record<string, Object> {
  return value as Record<string, Object>;
}

export function asObjectArray(value: Object | undefined | null): Object[] {
  if (value === undefined || value === null) {
    return [];
  }
  if (Array.isArray(value)) {
    return value as Object[];
  }
  return [];
}

export function asString(value: Object | undefined | null, fallback: string = ''): string {
  if (value === undefined || value === null) {
    return fallback;
  }
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  return fallback;
}

export function asStringArray(value: Object | undefined | null): string[] {
  if (!Array.isArray(value)) {
    return [];
  }
  const out: string[] = [];
  const list = value as Object[];
  for (let i = 0; i < list.length; i++) {
    const s = asString(list[i]);
    if (s) {
      out.push(s);
    }
  }
  return out;
}

export function asNumber(value: Object | undefined | null, fallback: number = 0): number {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value;
  }
  if (typeof value === 'string') {
    const n = Number(value);
    if (Number.isFinite(n)) {
      return n;
    }
  }
  return fallback;
}

export function asBool(value: Object | undefined | null, fallback: boolean = false): boolean {
  if (typeof value === 'boolean') {
    return value;
  }
  return fallback;
}

export function recGet(obj: Record<string, Object>, key: string): Object | undefined {
  return obj[key];
}

export function joinSpokenText(existing: string, spoken: string): string {
  const addition = spoken.replace(/\s+/g, ' ').trim();
  if (!addition) {
    return existing;
  }
  const base = existing.replace(/\s+$/, '');
  if (!base) {
    return addition;
  }
  if (/[，。！？、；：,.!?;:）)】」』]$/.test(base)) {
    return `${base}${addition}`;
  }
  const last = base.slice(-1);
  const first = addition.slice(0, 1);
  if (/[A-Za-z0-9]/.test(last) && /[A-Za-z0-9]/.test(first)) {
    return `${base} ${addition}`;
  }
  return `${base}${addition}`;
}

export function splitTips(text: string): string[] {
  const parts = text.split(/[；;。]/);
  const out: string[] = [];
  for (let i = 0; i < parts.length; i++) {
    const s = parts[i].replace(/^、\s*/, '').trim();
    if (s) {
      out.push(s);
    }
  }
  return out;
}

export function shuffleCopy<T>(items: T[]): T[] {
  const next: T[] = items.slice();
  for (let i = next.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    const tmp = next[i];
    next[i] = next[j];
    next[j] = tmp;
  }
  return next;
}
