import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { AppConfig } from '../common/AppConfig';
import { AppContextHolder } from '../common/AppContextHolder';
import { PreferencesStore } from '../common/PreferencesStore';
import { asrService } from '../speech/AsrService';
import { ttsService } from '../speech/TtsService';
import { AuthStore } from '../store/AuthStore';
import { BankStore } from '../store/BankStore';
import { LlmStore } from '../store/LlmStore';
import { ProgressStore } from '../store/ProgressStore';
import { ResumeStore } from '../store/ResumeStore';

export default class EntryAbility extends UIAbility {
  onCreate(_want: Want, _launchParam: AbilityConstant.LaunchParam): void {
    AppContextHolder.context = this.context;
    void this.bootstrap();
  }

  private async bootstrap(): Promise<void> {
    try {
      await PreferencesStore.init(this.context);
      const base = await PreferencesStore.get(AppConfig.BASE_PREF, '');
      try {
        AppConfig.currentBase = AppConfig.resolveApiBase(base);
      } catch (_e) {
        AppConfig.currentBase = AppConfig.defaultBase();
      }
      hilog.info(0x0000, 'Interview', 'api base %{public}s', AppConfig.currentBase);
      await ProgressStore.load();
      await AuthStore.bootstrap();
      void LlmStore.load();
      void BankStore.load();
    } catch (e) {
      const err = e as Error;
      hilog.error(0x0000, 'Interview', 'bootstrap %{public}s', err.message);
      AuthStore.ready = true;
      AuthStore.emit();
    }
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    AppContextHolder.windowStage = windowStage;
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(0x0000, 'Interview', 'loadContent %{public}s', JSON.stringify(err));
      }
    });
  }

  onWindowStageDestroy(): void {
    AppContextHolder.windowStage = undefined;
  }

  onDestroy(): void {
    ttsService.stop();
    void asrService.stop();
    ResumeStore.cancelPoll();
    AppContextHolder.context = undefined;
  }
}
