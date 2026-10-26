import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { DockBarMaterial } from './ImmersiveDockModifier';

/** Side-rail glass: API 26+ system material, otherwise the API 23 dock blur. */
export class CompatibleRailModifier implements AttributeModifier<CommonAttribute> {
  private darkMode: boolean;

  constructor(darkMode: boolean) {
    this.darkMode = darkMode;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (DockBarMaterial.applyRail(instance, deviceInfo.apiAvailable('27.0.0') ? 1 : 0)) {
        return;
      }
    }
    instance.backgroundEffect({
      radius: 24, saturation: 1.1, brightness: 1,
      color: this.darkMode ? '#66101214' : '#44F1F3F5'
    });
    instance.border({ width: 0.5, color: this.darkMode ? '#33FFFFFF' : '#88FFFFFF' });
  }
}
