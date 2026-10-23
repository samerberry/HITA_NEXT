/**
 * EasSilentLoginWeb.ets — 静默续期使用的离屏 Web 组件，不挂到任何页面，用户看不到。
 */
import { webview } from '@kit.ArkWeb';
import { BuilderNode, UIContext } from '@kit.ArkUI';
import { EasCampus } from '../EasSession';
import { EasSessionRenewal } from '../EasSessionRenewal';
import { EasSilentLogin, EasSilentWebMount } from './EasSilentLogin';

/** 手机竖屏尺寸，让认证页脚本按正常视口布局。 */
const SILENT_WEB_WIDTH: number = 390;
const SILENT_WEB_HEIGHT: number = 844;

class EasSilentWebParams {
  url: string;
  controller: webview.WebviewController;
  login: EasSilentLogin;

  constructor(url: string, controller: webview.WebviewController, login: EasSilentLogin) {
    this.url = url;
    this.controller = controller;
    this.login = login;
  }
}

@Builder
function silentLoginWeb(params: EasSilentWebParams) {
  Web({ src: params.url, controller: params.controller })
    .domStorageAccess(true)
    .javaScriptAccess(true)
    .databaseAccess(true)
    .mixedMode(MixedMode.All)
    .multiWindowAccess(true)
    .allowWindowOpenMethod(true)
    .onWindowNew((event) => {
      params.login.windowNew(event !== undefined && event !== null && event.targetUrl ? event.targetUrl : '');
    })
    .onControllerAttached(() => {
      params.login.attached();
    })
    .onPageBegin((event) => {
      params.login.pageBegin(event !== undefined && event !== null ? event.url : '');
    })
    .onPageEnd((event) => {
      params.login.pageEnd(event !== undefined && event !== null ? event.url : '');
    })
    .onLoadFinished((event) => {
      params.login.loadFinished(event !== undefined && event !== null ? event.url : '');
    })
    .onErrorReceive((event) => {
      if (event !== undefined && event !== null && event.request !== undefined && event.request.isMainFrame()) {
        params.login.mainFrameError(event.error !== undefined && event.error !== null ? event.error.getErrorInfo() : '');
      }
    })
    .width(SILENT_WEB_WIDTH)
    .height(SILENT_WEB_HEIGHT)
}

function silentWebMount(uiContext: UIContext): EasSilentWebMount {
  return (url: string, controller: webview.WebviewController, login: EasSilentLogin): () => void => {
    const node: BuilderNode<[EasSilentWebParams]> = new BuilderNode<[EasSilentWebParams]>(uiContext, {
      selfIdealSize: { width: SILENT_WEB_WIDTH, height: SILENT_WEB_HEIGHT }
    });
    node.build(wrapBuilder<[EasSilentWebParams]>(silentLoginWeb), new EasSilentWebParams(url, controller, login));
    return () => {
      node.dispose();
    };
  };
}

/** 主页面就绪后调用，使教务请求遇到认证失效时先尝试静默续期。 */
export function attachEasSilentRenewal(uiContext: UIContext): void {
  const mount: EasSilentWebMount = silentWebMount(uiContext);
  EasSessionRenewal.getInstance().attach((campus: EasCampus, studentType: string) =>
    new EasSilentLogin(campus, studentType).run(mount));
}
