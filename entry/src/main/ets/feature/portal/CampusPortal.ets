import { EasCampus } from '../eas/EasSession';

export class CampusPortalGroup {
  title: string;
  portals: CampusPortal[];

  constructor(title: string, portals: CampusPortal[]) {
    this.title = title;
    this.portals = portals;
  }
}

export class CampusPortal {
  title: string;
  url: string;
  icon: Resource;

  constructor(title: string, url: string, icon: Resource = $r('sys.symbol.link')) {
    this.title = title;
    this.url = url;
    this.icon = icon;
  }

  // HITA_Android UsefulLinksActivity + strings.xml, main 01ede97 (2026-10-13).
  private static readonly SHENZHEN_GROUPS: CampusPortalGroup[] = [
    new CampusPortalGroup('教学学习', [
      new CampusPortal('课程回放', 'https://jxypt.hitsz.edu.cn/ve', $r('sys.symbol.clock')),
      new CampusPortal('本研平台', 'https://jw.hitsz.edu.cn/', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('实验选课', 'https://lab.hitsz.edu.cn/', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('教评网', 'https://hitsz.mycospxk.com/', $r('sys.symbol.doc_text')),
      new CampusPortal('Grader 评测', 'https://grader.hitsz.edu.cn/home', $r('sys.symbol.checkmark')),
      new CampusPortal('实验指导书仓库', 'https://git.cs-lab.top/cslab', $r('sys.symbol.doc_plaintext'))
    ]),
    new CampusPortalGroup('信息与事务', [
      new CampusPortal('信息门户', 'https://www.hitsz.edu.cn/'),
      new CampusPortal('信息学部', 'https://cist.hitsz.edu.cn/index.htm'),
      new CampusPortal('校内通知', 'https://info.hitsz.edu.cn/', $r('sys.symbol.doc_text')),
      new CampusPortal('学生工作网', 'https://xgb.hit.edu.cn/'),
      new CampusPortal('交学费', 'https://xuefei.hitsz.edu.cn/'),
      new CampusPortal('思政实践平台', 'http://szsj.hitsz.edu.cn/index/index/index.html')
    ]),
    new CampusPortalGroup('网络与系统', [
      new CampusPortal('校园网', 'https://net.hitsz.edu.cn/'),
      new CampusPortal('HPC 服务', 'http://hpc.hitsz.edu.cn/'),
      new CampusPortal('仪器共享系统', 'https://17.hitsz.edu.cn/'),
      new CampusPortal('邮箱', 'https://mail.hit.edu.cn/')
    ]),
    new CampusPortalGroup('资源', [
      new CampusPortal('HOA 课程资源', 'https://hoa.moe/', $r('sys.symbol.magnifyingglass')),
      new CampusPortal('HOA 文件高速下载', 'https://gh.hoa.moe/', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('线上买教材', 'http://www.hitsz.textbook.wang/textbooks/home/index')
    ])
  ];

  private static readonly BENBU_GROUPS: CampusPortalGroup[] = [
    new CampusPortalGroup('教学学习', [
      new CampusPortal('本科教学管理与服务平台', 'http://jwts.hit.edu.cn', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('本科生网上服务系统', 'http://jwes.hit.edu.cn', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('电路选课', 'http://eelab.hit.edu.cn', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('本科生院官网', 'https://hituc.hit.edu.cn'),
      new CampusPortal('图书馆', 'http://www.lib.hit.edu.cn', $r('sys.symbol.magnifyingglass'))
    ]),
    new CampusPortalGroup('信息与事务', [
      new CampusPortal('学校官网', 'https://www.hit.edu.cn'),
      new CampusPortal('今日哈工大', 'http://today.hit.edu.cn', $r('sys.symbol.doc_text')),
      new CampusPortal('哈工大新闻网', 'http://news.hit.edu.cn', $r('sys.symbol.doc_text')),
      new CampusPortal('未来技术学院官网', 'https://future.hit.edu.cn'),
      new CampusPortal('学工系统', 'https://xg.hit.edu.cn'),
      new CampusPortal('后勤网上服务大厅', 'http://hqfw.hit.edu.cn'),
      new CampusPortal('校园地图', 'http://map.hit.edu.cn', $r('sys.symbol.pin'))
    ]),
    new CampusPortalGroup('网络与系统', [
      new CampusPortal('校园门户', 'http://i.hit.edu.cn'),
      new CampusPortal('VPN 通道', 'https://vpn.hit.edu.cn')
    ]),
    new CampusPortalGroup('资源', [
      new CampusPortal('哈工大教师主页', 'https://homepage.hit.edu.cn', $r('sys.symbol.person_crop_circle_fill'))
    ])
  ];

  private static readonly WEIHAI_GROUPS: CampusPortalGroup[] = [
    new CampusPortalGroup('教学学习', [
      new CampusPortal('本科教务', 'http://jwts.hitwh.edu.cn/', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('研究生教务', 'https://yjsgl.hitwh.edu.cn/', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('图书馆', 'http://lib.hitwh.edu.cn', $r('sys.symbol.magnifyingglass')),
      new CampusPortal('大学物理实验', 'http://wlsy.hitwh.edu.cn/', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('物理实验计算工具', 'https://y.cybzh.cn/', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('电工电子实验', 'http://ilab.hitwh.edu.cn/', $r('sys.symbol.doc_plaintext')),
      new CampusPortal('实验室系统', 'http://openlab.hitwh.edu.cn/#/login?redirect=/index', $r('sys.symbol.doc_plaintext'))
    ]),
    new CampusPortalGroup('信息与事务', [
      new CampusPortal('校区新闻', 'http://news.hitwh.edu.cn/1040/list.htm', $r('sys.symbol.doc_text')),
      new CampusPortal('校区通知', 'http://today.hitwh.edu.cn/1024/list.htm', $r('sys.symbol.doc_text')),
      new CampusPortal('学工系统', 'http://xuegong.hitwh.edu.cn/'),
      new CampusPortal('就业系统', 'http://job.hitwh.edu.cn/signout'),
      new CampusPortal('校长信箱', 'http://box.hitwh.edu.cn/'),
      new CampusPortal('场地预约', 'https://space.hit.edu.cn/cdyygl', $r('sys.symbol.calendar'))
    ]),
    new CampusPortalGroup('网络与系统', [
      new CampusPortal('校园门户', 'https://i.hitwh.edu.cn/'),
      new CampusPortal('VPN', 'https://ivpn.hitwh.edu.cn'),
      new CampusPortal('数据库VPN', 'https://webvpn.hitwh.edu.cn'),
      new CampusPortal('办公系统', 'http://oa.hitwh.edu.cn/'),
      new CampusPortal('身份认证', 'https://ids.hit.edu.cn/authserver/login', $r('sys.symbol.lock_shield')),
      new CampusPortal('电子邮箱', 'https://mail.hit.edu.cn')
    ]),
    new CampusPortalGroup('资源', [
      new CampusPortal('教师主页', 'http://homepage.hit.edu.cn/home-index', $r('sys.symbol.person_crop_circle_fill')),
      new CampusPortal('资料共享站', 'https://qqptr.top/', $r('sys.symbol.doc_plaintext'))
    ])
  ];

  static groupsFor(campus: EasCampus | undefined): CampusPortalGroup[] {
    switch (campus) {
      case EasCampus.BENBU: return CampusPortal.BENBU_GROUPS;
      case EasCampus.SHENZHEN: return CampusPortal.SHENZHEN_GROUPS;
      case EasCampus.WEIHAI: return CampusPortal.WEIHAI_GROUPS;
      default: return [];
    }
  }

  static campusName(campus: EasCampus | undefined): string {
    switch (campus) {
      case EasCampus.BENBU: return '本部';
      case EasCampus.SHENZHEN: return '深圳';
      case EasCampus.WEIHAI: return '威海';
      default: return '';
    }
  }
}
