/**
 * ImmersiveDockModifier.ets — 底部 dock 沉浸光感（组件适配）。
 *
 * HarmonyOS 7 / API 26 的 systemMaterial 支持标题栏和底部 TabBar 区域。
 * 因此材质挂在 Tabs.barFloatingStyle.systemMaterial，而不是自定义 Stack。
 *
 * @see https://developer.huawei.com/consumer/cn/doc/doccenter-advanced-features/bpta-spatiality-immersive
 * @see https://developer.huawei.com/consumer/cn/doc/doccenter-references/api/arkts-apis-uimaterial
 */
import { uiMaterial } from '@kit.ArkUI';
import { Available } from '@kit.BasicServicesKit';
import { dockWhiteLightColor } from '../util/DockLightEffect';
import { DOCK_SIDE_MARGIN, DOCK_NAV_WIDTH } from '../util/DockHandedness';

@Available({ minApiVersion: 'HarmonyOS 26.0.0' })
export class DockBarMaterial {
  static floatingStyle(bottomMargin: number, hideMask: boolean = false,
    darkMode: boolean = false, lightAlpha: number = 0, handedness: boolean = false): FloatingTabBarStyle {
    const style: FloatingTabBarStyle = {
      barWidth: {
        smallBarWidth: DOCK_NAV_WIDTH,
        mediumBarWidth: DOCK_NAV_WIDTH,
        largeBarWidth: DOCK_NAV_WIDTH
      },
      barBottomMargin: bottomMargin,
      // 智感握姿：单手握持时页签栏移向握持侧，边距与自绘光效的位移计算一致。
      adaptToHandedness: handedness,
      barSideMargin: DOCK_SIDE_MARGIN,
      maskColor: hideMask ? Color.Transparent : (darkMode ? '#99101214' : '#66F1F3F5'),
      maskHeight: hideMask ? 0 : 92
    };
    const material: uiMaterial.ImmersiveMaterial | undefined = DockBarMaterial.material(lightAlpha);
    if (material !== undefined) {
      style.systemMaterial = material;
    }
    return style;
  }

  /** The same glass for the bottom bar and the tablet side rail. */
  static material(lightAlpha: number = 0): uiMaterial.ImmersiveMaterial | undefined {
    try {
      if (uiMaterial.isImmersiveMaterialSupported()) {
        return new uiMaterial.ImmersiveMaterial({
          style: DockBarMaterial.styleForDevice(),
          applyShadow: true,
          // 按背景亮度反色，避免深色课表上图标发灰；具体色值走系统文本色，避免纯黑超对比度上限。
          colorInvert: true,
          // Keep the light white in both themes; opacity controls its strength.
          interactive: true,
          lightEffect: lightAlpha <= 0 ? null : { color: dockWhiteLightColor(lightAlpha) }
        });
      }
    } catch (e) {
      // 设备或 API 不支持时，悬浮栏仍保留圆角与蒙层。
    }
    return undefined;
  }

  /** Returns false when the rail must draw its own blurred fallback. */
  static applyRail(instance: CommonAttribute, lightAlpha: number): boolean {
    const material: uiMaterial.ImmersiveMaterial | undefined = DockBarMaterial.material(lightAlpha);
    if (material === undefined) {
      return false;
    }
    instance.backgroundColor(Color.Transparent);
    instance.systemMaterial(material);
    return true;
  }

  private static styleForDevice(): uiMaterial.ImmersiveStyle {
    try {
      const level: uiMaterial.MaterialLevel = uiMaterial.getGlobalMaterialLevel();
      if (level === uiMaterial.MaterialLevel.EXQUISITE) {
        return uiMaterial.ImmersiveStyle.ULTRA_THIN;
      }
      if (level === uiMaterial.MaterialLevel.GENTLE) {
        return uiMaterial.ImmersiveStyle.THIN;
      }
    } catch (e) {
      // 回落到薄材质。
    }
    return uiMaterial.ImmersiveStyle.THIN;
  }
}
