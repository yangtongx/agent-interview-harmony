import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

const PREF_NAME = 'interview_prefs';

export class PreferencesStore {
  private static pref: preferences.Preferences | null = null;

  static async init(context: common.UIAbilityContext): Promise<void> {
    PreferencesStore.pref = await preferences.getPreferences(context, PREF_NAME);
  }

  static async get(key: string, def: string = ''): Promise<string> {
    if (!PreferencesStore.pref) {
      return def;
    }
    const v = await PreferencesStore.pref.get(key, def);
    return String(v ?? def);
  }

  static async set(key: string, value: string): Promise<void> {
    if (!PreferencesStore.pref) {
      return;
    }
    await PreferencesStore.pref.put(key, value);
    await PreferencesStore.pref.flush();
  }
}
