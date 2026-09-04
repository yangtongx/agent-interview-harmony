import { common } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';

export class AppContextHolder {
  static context: common.UIAbilityContext | undefined = undefined;
  static windowStage: window.WindowStage | undefined = undefined;

  static filesDir(): string {
    if (!AppContextHolder.context) {
      return '';
    }
    return AppContextHolder.context.filesDir;
  }

  static async setKeepScreenOn(on: boolean): Promise<void> {
    const stage = AppContextHolder.windowStage;
    const ctx = AppContextHolder.context;
    if (!stage || !ctx) {
      return;
    }
    try {
      const win = await window.getLastWindow(ctx);
      await win.setWindowKeepScreenOn(on);
    } catch (_e) {
    }
  }
}
