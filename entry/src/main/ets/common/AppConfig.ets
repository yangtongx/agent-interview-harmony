import { BuildFlags } from './BuildFlags';

export class AppConfig {
  static readonly DEFAULT_BASE: string = 'https://www.xiaoyangtx.cloud';
  /** Debug HAP default. Phone must reach this PC on the same LAN; change if DHCP moves. */
  static readonly LOCAL_DEBUG_BASE: string = 'http://192.168.43.77:43180';
  static readonly BASE_PREF: string = 'api_base_url';
  static readonly LLM_PREF: string = 'ali-agent-interview-llm';
  static readonly MASTERED_PREF: string = 'ali-agent-interview-mastered';
  static readonly TOKEN_PREF: string = 'auth_token';
  static readonly DEVICE_PREF: string = 'device_id';
  static readonly USER_PREF: string = 'auth_user';
  static readonly AUTH_ENTERED_PREF: string = 'auth_entered';
  static readonly BANK_CACHE: string = 'bank-cache.json';
  static readonly BANK_ETAG: string = 'bank-cache.etag';
  static readonly CONNECT_TIMEOUT: number = 30000;
  static readonly READ_TIMEOUT: number = 120000;
  static readonly MAX_TTS_CHARS: number = 560;
  static currentBase: string = AppConfig.DEFAULT_BASE;
  static sessionToken: string = '';

  static isHttpsUrl(url: string): boolean {
    const trimmed = url.trim().toLowerCase();
    return trimmed.startsWith('https://') && trimmed.length > 8;
  }

  static defaultBase(): string {
    return BuildFlags.allowCleartext() ? AppConfig.LOCAL_DEBUG_BASE : AppConfig.DEFAULT_BASE;
  }

  static isProductionBase(url: string): boolean {
    return url.trim().replace(/\/+$/, '').toLowerCase() === AppConfig.DEFAULT_BASE.toLowerCase();
  }

  static resolveApiBase(stored: string): string {
    const raw = stored.trim();
    if (!raw || (BuildFlags.allowCleartext() && AppConfig.isProductionBase(raw))) {
      return AppConfig.defaultBase();
    }
    return AppConfig.normalizeApiBase(raw);
  }

  static normalizeApiBase(url: string): string {
    const trimmed = url.trim().replace(/\/+$/, '');
    const next = trimmed ? trimmed : AppConfig.defaultBase();
    const lower = next.toLowerCase();
    if (lower.startsWith('https://') && next.length > 8) {
      return next;
    }
    if (BuildFlags.allowCleartext() && lower.startsWith('http://') && next.length > 7) {
      return next;
    }
    throw new Error(BuildFlags.allowCleartext()
      ? '站点地址必须以 http:// 或 https:// 开头。'
      : '正式版本只允许 HTTPS 站点。');
  }
}

export class Theme {
  static readonly paper: string = '#F6F0E6';
  static readonly card: string = '#FFFDF8';
  static readonly ink: string = '#1C1410';
  static readonly muted: string = '#7A6F66';
  static readonly accent: string = '#E24A16';
  static readonly accentSoft: string = '#FBE4D6';
  static readonly emerald: string = '#0F7A5A';
  static readonly emeraldSoft: string = '#E3F4EC';
  static readonly danger: string = '#C43C2C';
  static readonly dangerSoft: string = '#F8E4E0';
  static readonly line: string = '#E8DFD4';
}
