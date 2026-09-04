import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../common/AppConfig';
import { Emitter } from '../common/Emitter';
import { parseHome } from '../model/Parse';
import { HomePayload } from '../model/Types';
import { ApiClient } from '../network/ApiClient';

export class HomeStore {
  static home: HomePayload | null = null;
  private static bus: Emitter = new Emitter();

  static subscribe(fn: () => void): () => void {
    return HomeStore.bus.subscribe(fn);
  }

  static emit(): void {
    HomeStore.bus.emit();
  }

  static async load(audience: string = ''): Promise<void> {
    if (!AppConfig.sessionToken || !audience || audience === 'unset') {
      HomeStore.home = null;
      HomeStore.emit();
      return;
    }
    try {
      const text = await ApiClient.getText(`/api/home?audience=${audience}`);
      HomeStore.home = parseHome(text);
      HomeStore.emit();
    } catch (e) {
      hilog.error(0x0000, 'Interview', 'home %{public}s', (e as Error).message);
      HomeStore.home = null;
      HomeStore.emit();
    }
  }
}
