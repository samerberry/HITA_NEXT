import { webview } from '@kit.ArkWeb';

export class EasWebLoginState {
  /** Signs the in-app web views out of every school site: CAS, VPN and EAS cookies plus page storage. */
  static async clear(): Promise<void> {
    await webview.WebCookieManager.clearAllCookies();
    webview.WebStorage.deleteAllData();
  }
}
