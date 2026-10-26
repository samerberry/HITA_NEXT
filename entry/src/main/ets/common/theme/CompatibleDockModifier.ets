import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { DockBarMaterial } from './ImmersiveDockModifier';

/** Keep the API 26 material module unloaded on older systems. */
export class CompatibleDockModifier implements AttributeModifier<TabsAttribute> {
  private bottomMargin: number;
  private hideMask: boolean;
  private darkMode: boolean;
  private handedness: boolean;
  private rail: boolean;
  constructor(bottomMargin: number, hideMask: boolean, darkMode: boolean, handedness: boolean = false,
    rail: boolean = false) {
    this.bottomMargin = bottomMargin;
    this.hideMask = hideMask;
    this.darkMode = darkMode;
    this.handedness = handedness;
    this.rail = rail;
  }

  applyNormalAttribute(instance: TabsAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (this.rail) {
        // The side rail replaces the floating bar; clear its mask and margins too.
        instance.barFloatingStyle(undefined);
        return;
      }
      instance.barFloatingStyle(DockBarMaterial.floatingStyle(
        this.bottomMargin, this.hideMask, this.darkMode,
        deviceInfo.apiAvailable('27.0.0') ? 1 : 0, this.handedness));
    }
  }
}
