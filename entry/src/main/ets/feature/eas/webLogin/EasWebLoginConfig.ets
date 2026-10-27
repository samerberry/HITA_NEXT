/**
 * EasWebLoginConfig.ets — 三校区 CampusConfig 表（ArkTS 侧直接作为配置文件）。
 *
 * 校区 URL、User-Agent 和 Cookie 探针配置参考 HITA Android。
 * 页面与会话判定见 EasWebLoginProbe.ets。
 */
import { EasCampus } from '../EasSession';

/** 校园统一认证/门户 URL 常量（对应 CampusUrls 全部静态量）。 */
export class EasCampusUrls {
  // —— 深圳 ——
  static readonly SHENZHEN_PROXY_BASE: string = 'https://jw-hitsz-edu-cn.hitsz.edu.cn';
  static readonly SHENZHEN_DIRECT_BASE: string = 'https://jw.hitsz.edu.cn';
  static readonly SHENZHEN_LOGIN: string = 'https://jw-hitsz-edu-cn.hitsz.edu.cn/';
  static readonly SHENZHEN_JWTS: string = 'https://jw-hitsz-edu-cn.hitsz.edu.cn/authentication/main';

  // —— 本部（VPN）——
  static readonly BENBU_BASE: string = 'http://i-hit-edu-cn.ivpn.hit.edu.cn:1080';
  static readonly JWTS_BASE: string = 'http://jwts-hit-edu-cn.vpn.hit.edu.cn:1080';
  static readonly GRADUATE_BASE: string = 'http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080';
  static readonly EELABINFO_URL: string = 'http://eelabinfo-hit-edu-cn.ivpn.hit.edu.cn:1080';
  /** 实验教学管理系统（sjjx）：经 jwts 的 /loginsysj/loginSygl 桥接后使用 */
  static readonly SJJX_BASE: string = 'http://sjjx-hit-edu-cn.ivpn.hit.edu.cn:1080';
  static readonly BENBU_LOGIN: string = 'http://i-hit-edu-cn.ivpn.hit.edu.cn:1080/portal/home/';
  static readonly BENBU_JWTS: string = EasCampusUrls.JWTS_BASE + '/loginCAS';
  static readonly BENBU_GRADUATE_JWTS: string = 'http://yjsgl-hit-edu-cn.ivpn.hit.edu.cn:1080/common/casLogin';

  // —— 威海（webvpn）——
  static readonly WEIHAI_BASE: string = 'https://webvpn.hitwh.edu.cn';
  static readonly WEIHAI_EAS_PREFIX: string =
    'https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667';
  static readonly WEIHAI_LOGIN: string = 'https://webvpn.hitwh.edu.cn/';
  static readonly WEIHAI_JWTS: string =
    'https://webvpn.hitwh.edu.cn/http/77726476706e69737468656265737421fae0558f693861446900c7a99c406d3667/loginCAS';
}

/** 深圳 Cookie 探针 URL（对应 WebLoginSuccessPolicy.shenzhenCookieProbeUrls）。 */
function buildShenzhenCookieProbeUrls(proxyBaseUrl: string, directBaseUrl: string): string[] {
  const paths: string[] = ['/authentication/main', '/student_index', '/user/me', '/'];
  const rawBases: string[] = [proxyBaseUrl, directBaseUrl];
  const bases: string[] = [];
  const seen: Set<string> = new Set<string>();
  for (let i = 0; i < rawBases.length; i++) {
    const normalized: string = rawBases[i].replace(/\/+$/, '').toLowerCase();
    if (!seen.has(normalized)) {
      seen.add(normalized);
      bases.push(rawBases[i]);
    }
  }
  const out: string[] = [];
  for (let i = 0; i < bases.length; i++) {
    const base: string = bases[i].replace(/\/+$/, '');
    for (let j = 0; j < paths.length; j++) {
      out.push(base + paths[j]);
    }
  }
  return out;
}

/**
 * 深圳登录基址选择：true=直连 jw.hitsz.edu.cn（适合非校园网，先验证浏览器可达性）；
 * false=代理 jw-hitsz-edu-cn.hitsz.edu.cn（校园网/代理场景，与原版 CampusUrls 一致）。
 * 抓包确认新版真实登录域名后可在此或 EasCampusUrls 调整。
 */
export const SHENZHEN_LOGIN_VIA_DIRECT: boolean = false;

/** 单校区 Web 登录配置（对应 CampusWebConfig + 登录所需扩展）。 */
export class EasCampusConfig {
  readonly campus: EasCampus;
  readonly loginUrl: string;
  readonly jwtsUrl: string;
  readonly cookieProbeUrls: string[];
  /** "1"=本科 / "2"=研究生（默认 "1"；仅本部区分）。 */
  readonly studentType: string;
  /** 供 HTTP 数据访问合并 Cookie 的域集合（ArkTS 侧扩展，抓包阶段校准）。 */
  readonly cookieDomains: string[];
  /** 展示名。 */
  readonly displayName: string;

  constructor(campus: EasCampus, loginUrl: string, jwtsUrl: string, cookieProbeUrls: string[],
    studentType: string, cookieDomains: string[], displayName: string) {
    this.campus = campus;
    this.loginUrl = loginUrl;
    this.jwtsUrl = jwtsUrl;
    this.cookieProbeUrls = cookieProbeUrls;
    this.studentType = studentType;
    this.cookieDomains = cookieDomains;
    this.displayName = displayName;
  }
}

/** 按 校区×培养层次 取配置。 */
export function easWebLoginConfigFor(campus: EasCampus, studentType: string): EasCampusConfig {
  if (campus === EasCampus.SHENZHEN) {
    // 对齐安卓 CampusWebConfig(campus = SHENZHEN, loginUrl = SHENZHEN_JWTS, jwtsUrl = SHENZHEN_JWTS)
    // 携带 /authentication/main 目标地址进入，确保网关正确定向并保留回跳地址
    const szLogin: string = SHENZHEN_LOGIN_VIA_DIRECT ?
      EasCampusUrls.SHENZHEN_DIRECT_BASE + '/authentication/main' : EasCampusUrls.SHENZHEN_JWTS;
    const normalizedStudentType: string = studentType !== undefined && studentType !== null &&
      studentType.trim() === '2' ? '2' : '1';
    return new EasCampusConfig(
      EasCampus.SHENZHEN,
      szLogin,
      EasCampusUrls.SHENZHEN_JWTS,
      buildShenzhenCookieProbeUrls(EasCampusUrls.SHENZHEN_PROXY_BASE, EasCampusUrls.SHENZHEN_DIRECT_BASE),
      normalizedStudentType,
      ['jw.hitsz.edu.cn', 'jw-hitsz-edu-cn.hitsz.edu.cn'],
      '深圳'
    );
  }
  if (campus === EasCampus.WEIHAI) {
    return new EasCampusConfig(
      EasCampus.WEIHAI,
      EasCampusUrls.WEIHAI_LOGIN,
      EasCampusUrls.WEIHAI_JWTS,
      [
        EasCampusUrls.WEIHAI_JWTS,
        EasCampusUrls.WEIHAI_EAS_PREFIX + '/kjscx/queryJxlListBySjid',
        EasCampusUrls.WEIHAI_EAS_PREFIX + '/kbcx/queryGrkb',
        EasCampusUrls.WEIHAI_EAS_PREFIX + '/cjcx/queryQmcj',
        EasCampusUrls.WEIHAI_LOGIN
      ],
      '1',
      ['webvpn.hitwh.edu.cn'],
      '威海'
    );
  }
  // BENBU：按培养层次选 jwts/探针（对应 CampusUrls 本科/研究生两套）。
  const isGrad: boolean = studentType !== null && studentType !== undefined && studentType.trim() === '2';
  if (isGrad) {
    return new EasCampusConfig(
      EasCampus.BENBU,
      EasCampusUrls.BENBU_LOGIN,
      EasCampusUrls.BENBU_GRADUATE_JWTS,
      [
        EasCampusUrls.BENBU_GRADUATE_JWTS,
        EasCampusUrls.GRADUATE_BASE + '/xs/index',
        EasCampusUrls.GRADUATE_BASE + '/'
      ],
      '2',
      ['i-hit-edu-cn.ivpn.hit.edu.cn', 'yjsgl-hit-edu-cn.ivpn.hit.edu.cn', 'jwts-hit-edu-cn.vpn.hit.edu.cn'],
      '本部(研究生)'
    );
  }
  return new EasCampusConfig(
    EasCampus.BENBU,
    EasCampusUrls.BENBU_JWTS,
    EasCampusUrls.BENBU_JWTS,
    [
      EasCampusUrls.JWTS_BASE + '/kbcx/queryGrkb',
      EasCampusUrls.BENBU_JWTS,
      EasCampusUrls.JWTS_BASE + '/',
      EasCampusUrls.BENBU_BASE + '/',
      EasCampusUrls.BENBU_LOGIN
    ],
    '1',
    ['i-hit-edu-cn.ivpn.hit.edu.cn', 'jwts-hit-edu-cn.vpn.hit.edu.cn'],
    '本部'
  );
}

/**
 * UA 常量（对应 Activity L229 等）。
 * SHENZHEN_DESKTOP_USER_AGENT：门户强制 Web 模式 / 桌面 UA 修补用。
 * 其余校区沿用 WebView 运行时 UA（原版逻辑：先取系统默认再按需替换/恢复）。
 */
export class EasUserAgent {
  static readonly SHENZHEN_DESKTOP: string =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
  /** 原版 Android 端记录的出厂 Mobile UA 样例（仅参考；鸿蒙侧以 ArkWeb 实际默认 UA 为恢复值）。 */
  static readonly ANDROID_MOBILE_REF: string =
    'Mozilla/5.0 (Linux; Android 16; sdk_gphone64_arm64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.135 Mobile Safari/537.36';
}

/** 学生类型常量（对应 ShenzhenWebAutoLogin.UNDERGRAD/POSTGRAD）。 */
export class EasStudentTypeValue {
  static readonly UNDERGRAD: string = '1';
  static readonly POSTGRAD: string = '2';
}
