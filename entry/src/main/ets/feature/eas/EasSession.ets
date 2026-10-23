/**
 * EasSession.ets — 教务会话模型，兼容 HITA Android 的 EASToken 数据语义。
 *
 * 登录主产物是 webCookies（门户 Cookie）；cookies 为自有后端/旧式会话（本整合可空）。
 */

/** 校区枚举（对应 EASToken.Campus: SHENZHEN/BENBU/WEIHAI）。 */
export enum EasCampus {
  SHENZHEN = 'SHENZHEN',
  BENBU = 'BENBU',
  WEIHAI = 'WEIHAI'
}

/** 培养层次（对应 EASToken.TYPE: UNDERGRAD/GRAD → studentType "1"/"2"）。 */
export enum EasStudentType {
  UNDERGRAD = 'UNDERGRAD',
  GRAD = 'GRAD'
}

export class EasSession {
  // —— 会话核心 ——
  campus: EasCampus = EasCampus.SHENZHEN;
  /** 门户会话 Cookie（登录主产物） */
  webCookies: Map<string, string> = new Map<string, string>();
  /** 自有后端/旧式会话 Cookie（可空，兼容保留） */
  cookies: Map<string, string> = new Map<string, string>();
  /** 深圳实际数据基址（proxy 或 direct，登录完成后回填） */
  webBaseUrl: string = '';
  /** 本部电子实验(EELAB)额外 token */
  electronicExpToken: string = '';
  /** 本部实验教学系统(sjjx)会话 Cookie（经 jwts 的 /loginsysj/loginSygl 桥接取得） */
  sjjxCookies: Map<string, string> = new Map<string, string>();
  /** 会话代数：用于失效/刷新判定，每次重登 +1 */
  sessionGeneration: number = 0;
  /** 仅在实际教务请求确认认证失效后置为 true；重新登录成功时清除。 */
  loginExpired: boolean = false;

  // —— 自有后端 token（本整合可不使用）——
  accessToken: string = '';
  refreshToken: string = '';

  // —— 用户身份资料 ——
  username: string = '';
  name: string = '';
  password: string = '';
  stuId: string = '';
  school: string = '';
  grade: string = '';
  major: string = '';
  className: string = '';
  email: string = '';
  phone: string = '';
  picture: string = '';
  sfxsx: string = '';       // 学分数(深圳 GPA 相关展示字段，保留原名)
  id: string = '';
  /** 培养层次；持久化时转换为 studentType 字符串("1"/"2")。 */
  stutype: EasStudentType = EasStudentType.UNDERGRAD;

  /** EASToken.getStudentType(): "1"=本科(UNDERGRAD)，"2"=研究生(GRAD)。 */
  getStudentType(): string {
    return this.stutype === EasStudentType.GRAD ? '2' : '1';
  }

  setStudentType(raw: string): void {
    this.stutype = (raw !== null && raw !== undefined && raw.trim() === '2') ? EasStudentType.GRAD : EasStudentType.UNDERGRAD;
  }

  /** 对应 EASToken.isLogin()：accessToken 非空或任一 cookie 集合非空即视为有会话。 */
  isLogin(): boolean {
    const hasToken: boolean = this.accessToken.length > 0;
    return hasToken || this.cookies.size > 0 || this.webCookies.size > 0;
  }

  hasShenzhenWebSession(): boolean {
    return this.campus === EasCampus.SHENZHEN && EasSession.hasShenzhenWebSessionCookies(this.webCookies);
  }

  isBenbuCampus(): boolean {
    return this.campus === EasCampus.BENBU;
  }

  /** 换上另一次网页登录得到的会话凭据和代数；身份资料与自有后端 token 保持不变。 */
  adoptWebLogin(source: EasSession): void {
    this.webCookies = EasSession.copyMap(source.webCookies);
    this.webBaseUrl = source.webBaseUrl;
    this.electronicExpToken = source.electronicExpToken;
    this.sjjxCookies = EasSession.copyMap(source.sjjxCookies);
    this.sessionGeneration = source.sessionGeneration;
    this.loginExpired = source.loginExpired;
  }

  // ---------------------------------------------------------------------
  // 静态判定助手（对应 EASToken.Companion）
  // ---------------------------------------------------------------------

  /**
   * 深圳 Web 会话成立判据（与 Android EASToken.Companion 对齐）：
   * 直连使用非空 JSESSIONID + route；网页代理使用非空 SESSION。
   */
  static hasShenzhenWebSessionCookies(cookies: Map<string, string>): boolean {
    const hasDirectSession: boolean = EasSession.isNotBlank(cookies.get('JSESSIONID')) &&
      EasSession.isNotBlank(cookies.get('route'));
    const hasProxySession: boolean = EasSession.isNotBlank(cookies.get('SESSION'));
    return hasDirectSession || hasProxySession;
  }

  static isNotBlank(value: string | undefined): boolean {
    if (value === undefined || value === null) {
      return false;
    }
    return value.trim().length > 0;
  }

  /** 判断 Map 中某 key 是否存在且非空白（含误判保护）。 */
  static cookieValue(cookies: Map<string, string>, key: string): string {
    const v: string | undefined = cookies.get(key);
    return (v === undefined || v === null) ? '' : v;
  }

  /** 把 Cookie Map 合并为请求头 "k1=v1; k2=v2"（对应旧逻辑 buildCookieHeader）。 */
  static buildCookieHeader(cookies: Map<string, string>): string {
    const parts: string[] = [];
    cookies.forEach((value: string, key: string) => {
      if (EasSession.isNotBlank(key) && EasSession.isNotBlank(value)) {
        parts.push(key + '=' + value);
      }
    });
    return parts.join('; ');
  }

  // ---------------------------------------------------------------------
  // 序列化（Map 需显式编解码；敏感字段持久化前建议加密）
  // ---------------------------------------------------------------------

  encode(): string {
    const o: Record<string, Object> = {
      'campus': this.campus.toString(),
      'studentType': this.getStudentType(),
      'webCookies': EasSession.encodeMap(this.webCookies),
      'cookies': EasSession.encodeMap(this.cookies),
      'webBaseUrl': this.webBaseUrl,
      'electronicExpToken': this.electronicExpToken,
      'sjjxCookies': EasSession.encodeMap(this.sjjxCookies),
      'sessionGeneration': this.sessionGeneration,
      'loginExpired': this.loginExpired,
      'accessToken': this.accessToken,
      'refreshToken': this.refreshToken,
      'username': this.username,
      'name': this.name,
      'stuId': this.stuId,
      'school': this.school,
      'grade': this.grade,
      'major': this.major,
      'className': this.className,
      'email': this.email,
      'phone': this.phone,
      'picture': this.picture,
      'sfxsx': this.sfxsx,
      'id': this.id
    };
    return JSON.stringify(o);
  }

  static decode(raw: string): EasSession | undefined {
    try {
      const o: Record<string, Object> = JSON.parse(raw) as Record<string, Object>;
      const s: EasSession = new EasSession();
      const str = (k: string): string => {
        const v = o[k];
        return (v === undefined || v === null) ? '' : String(v);
      };
      const campusRaw: string = str('campus');
      if (campusRaw === EasCampus.BENBU.toString()) {
        s.campus = EasCampus.BENBU;
      } else if (campusRaw === EasCampus.WEIHAI.toString()) {
        s.campus = EasCampus.WEIHAI;
      } else {
        s.campus = EasCampus.SHENZHEN;
      }
      s.stutype = str('studentType') === '2' ? EasStudentType.GRAD : EasStudentType.UNDERGRAD;
      s.webCookies = EasSession.decodeMap(o['webCookies']);
      s.cookies = EasSession.decodeMap(o['cookies']);
      s.webBaseUrl = str('webBaseUrl');
      s.electronicExpToken = str('electronicExpToken');
      s.sjjxCookies = EasSession.decodeMap(o['sjjxCookies']);
      s.sessionGeneration = Number(o['sessionGeneration'] ?? 0);
      s.loginExpired = o['loginExpired'] === true;
      s.accessToken = str('accessToken');
      s.refreshToken = str('refreshToken');
      s.username = str('username');
      s.name = str('name');
      s.stuId = str('stuId');
      s.school = str('school');
      s.grade = str('grade');
      s.major = str('major');
      s.className = str('className');
      s.email = str('email');
      s.phone = str('phone');
      s.picture = str('picture');
      s.sfxsx = str('sfxsx');
      s.id = str('id');
      return s;
    } catch (e) {
      return undefined;
    }
  }

  static copyMap(m: Map<string, string>): Map<string, string> {
    const out: Map<string, string> = new Map<string, string>();
    m.forEach((value: string, key: string) => {
      out.set(key, value);
    });
    return out;
  }

  /** 编码成 {k,v}[]（JSON 安全）。 */
  static encodeMap(m: Map<string, string>): Array<Record<string, string>> {
    const out: Array<Record<string, string>> = [];
    m.forEach((value: string, key: string) => {
      out.push({ 'k': key, 'v': value });
    });
    return out;
  }

  static decodeMap(raw: Object | undefined): Map<string, string> {
    const out: Map<string, string> = new Map<string, string>();
    if (raw === undefined || raw === null) {
      return out;
    }
    try {
      const arr = raw as Array<Record<string, string>>;
      for (let i = 0; i < arr.length; i++) {
        const item: Record<string, string> = arr[i];
        if (item !== undefined && item !== null) {
          out.set(String(item['k']), String(item['v']));
        }
      }
    } catch (e) {
      // 解析失败保持空
    }
    return out;
  }
}
