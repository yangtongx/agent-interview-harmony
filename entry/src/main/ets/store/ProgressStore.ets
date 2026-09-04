import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../common/AppConfig';
import { Emitter } from '../common/Emitter';
import { PreferencesStore } from '../common/PreferencesStore';
import { parseStringList } from '../model/Parse';
import { ApiClient } from '../network/ApiClient';

export class ProgressStore {
  static ids: string[] = [];
  private static bus: Emitter = new Emitter();

  static subscribe(fn: () => void): () => void {
    return ProgressStore.bus.subscribe(fn);
  }

  static emit(): void {
    ProgressStore.bus.emit();
  }

  static has(id: string): boolean {
    return ProgressStore.ids.includes(id);
  }

  static merge(local: string[], remote: string[]): string[] {
    const seen: Record<string, boolean> = {};
    const out: string[] = [];
    const all = local.concat(remote);
    for (let i = 0; i < all.length; i++) {
      const id = all[i];
      if (!id || seen[id]) {
        continue;
      }
      seen[id] = true;
      out.push(id);
    }
    return out;
  }

  static async load(): Promise<void> {
    const raw = await PreferencesStore.get(AppConfig.MASTERED_PREF, '[]');
    ProgressStore.ids = parseStringList(raw);
    ProgressStore.emit();
  }

  static async replace(ids: string[]): Promise<void> {
    ProgressStore.ids = ids;
    await PreferencesStore.set(AppConfig.MASTERED_PREF, JSON.stringify(ProgressStore.ids));
    ProgressStore.emit();
  }

  static async pushRemote(): Promise<void> {
    if (!AppConfig.sessionToken) {
      return;
    }
    try {
      await ApiClient.putJson('/api/progress', { 'mastered': ProgressStore.ids });
    } catch (e) {
      hilog.error(0x0000, 'Interview', 'progress push %{public}s', (e as Error).message);
    }
  }

  static async toggle(id: string): Promise<void> {
    if (ProgressStore.ids.includes(id)) {
      ProgressStore.ids = ProgressStore.ids.filter((item: string) => item !== id);
    } else {
      ProgressStore.ids = ProgressStore.ids.concat([id]);
    }
    await PreferencesStore.set(AppConfig.MASTERED_PREF, JSON.stringify(ProgressStore.ids));
    ProgressStore.emit();
    await ProgressStore.pushRemote();
  }

  static draftKey(id: string): string {
    return `ali-agent-interview-draft:${id}`;
  }

  static async readDraft(id: string): Promise<string> {
    return PreferencesStore.get(ProgressStore.draftKey(id), '');
  }

  static async writeDraft(id: string, text: string): Promise<void> {
    await PreferencesStore.set(ProgressStore.draftKey(id), text);
  }
}
