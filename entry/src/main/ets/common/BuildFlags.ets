import { bundleManager } from '@kit.AbilityKit';

export class BuildFlags {
  private static resolved: boolean = false;
  private static value: boolean = false;

  static allowCleartext(): boolean {
    if (BuildFlags.resolved) {
      return BuildFlags.value;
    }
    try {
      const info = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION
      );
      BuildFlags.value = info.appInfo.debug === true;
      BuildFlags.resolved = true;
    } catch (_e) {
      return false;
    }
    return BuildFlags.value;
  }
}
