import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
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
      await LlmStore.load();
      await ProgressStore.load();
      await AuthStore.bootstrap();
      await BankStore.load();
    } catch (e) {
      const err = e as Error;
      hilog.error(0x0000, 'Interview', 'bootstrap %{public}s', err.message);
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
