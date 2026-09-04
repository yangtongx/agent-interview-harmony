import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../common/AppConfig';
import { Emitter } from '../common/Emitter';
import { PreferencesStore } from '../common/PreferencesStore';
import { SecureStore } from '../common/SecureStore';
import { parseLlmSettings } from '../model/Parse';
import { LlmSettings, chatModelFor } from '../model/Types';
import { ApiClient } from '../network/ApiClient';

export class LlmStore {
  static settings: LlmSettings = new LlmSettings();
  static serverConfigured: boolean = false;
  static apiBase: string = AppConfig.DEFAULT_BASE;
  private static bus: Emitter = new Emitter();

  static subscribe(fn: () => void): () => void {
    return LlmStore.bus.subscribe(fn);
  }

  static emit(): void {
    LlmStore.bus.emit();
  }

  static ready(): boolean {
    return LlmStore.settings.apiKey.trim().length > 0 || LlmStore.serverConfigured;
  }

  static async load(): Promise<void> {
    const raw = await PreferencesStore.get(AppConfig.LLM_PREF, '');
    if (raw) {
      LlmStore.settings = parseLlmSettings(raw);
    }
    const storedKey = await SecureStore.get('llm_api_key', '');
    if (storedKey) {
      LlmStore.settings.apiKey = storedKey;
    } else if (LlmStore.settings.apiKey) {
      await SecureStore.set('llm_api_key', LlmStore.settings.apiKey);
      await LlmStore.persistPublic();
    }
    const base = await PreferencesStore.get(AppConfig.BASE_PREF, AppConfig.DEFAULT_BASE);
    try {
      LlmStore.apiBase = AppConfig.normalizeApiBase(base);
    } catch (e) {
      hilog.error(0x0000, 'Interview', 'api base %{public}s', (e as Error).message);
      LlmStore.apiBase = AppConfig.DEFAULT_BASE;
    }
    AppConfig.currentBase = LlmStore.apiBase;
    LlmStore.serverConfigured = await ApiClient.getJudgeConfigured();
    LlmStore.emit();
  }

  private static async persistPublic(): Promise<void> {
    await PreferencesStore.set(AppConfig.LLM_PREF, JSON.stringify({
      'provider': LlmStore.settings.provider,
      'baseUrl': LlmStore.settings.baseUrl,
      'model': LlmStore.settings.model
    }));
  }

  static async save(next: LlmSettings): Promise<void> {
    next.model = chatModelFor(next);
    LlmStore.settings = next;
    await SecureStore.set('llm_api_key', next.apiKey);
    await LlmStore.persistPublic();
    LlmStore.emit();
  }

  static async saveBase(url: string): Promise<void> {
    LlmStore.apiBase = AppConfig.normalizeApiBase(url);
    AppConfig.currentBase = LlmStore.apiBase;
    await PreferencesStore.set(AppConfig.BASE_PREF, LlmStore.apiBase);
    LlmStore.serverConfigured = await ApiClient.getJudgeConfigured();
    LlmStore.emit();
  }

  static async refreshServer(): Promise<void> {
    LlmStore.serverConfigured = await ApiClient.getJudgeConfigured();
    LlmStore.emit();
  }
}
