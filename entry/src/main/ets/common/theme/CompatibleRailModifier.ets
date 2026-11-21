import { deviceInfo } from '@kit.BasicServicesKit';
import lazy { DockBarMaterial } from './ImmersiveDockModifier';

/** Dock glass: API 26+ system material, otherwise the API 23 dock blur. */
export class CompatibleRailModifier implements AttributeModifier<CommonAttribute> {
  private darkMode: boolean;
  private applyShadow: boolean;

  constructor(darkMode: boolean, applyShadow: boolean = true) {
    this.darkMode = darkMode;
    this.applyShadow = applyShadow;
  }

  applyNormalAttribute(instance: CommonAttribute): void {
    if (deviceInfo.apiAvailable('26.0.0')) {
      if (DockBarMaterial.applyRail(instance, 0, this.applyShadow)) {
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
