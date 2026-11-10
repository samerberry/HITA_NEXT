import { HitaDesign } from '../../common/theme/HitaDesign';
/**
 * 关于页与隐私政策的全部文案。改名单、致谢或政策条款时只改这里，页面只负责排版。
 * 提审前将隐私政策正文同步到华为协议托管服务（见 PRIVACY_POLICY_URL）。
 */

export class AboutContributor {
  /** 真实姓名，显示在第一行。 */
  name: string;
  /** GitHub 昵称，显示在第二行。 */
  github: string;
  /** 打包在 resources/base/media 中的 GitHub 头像。 */
  avatar: Resource;
  url: string;

  constructor(name: string, github: string, avatar: Resource, url: string) {
    this.name = name;
    this.github = github;
    this.avatar = avatar;
    this.url = url;
  }
}

export class AboutCredit {
  title: string;
  detail: string;
  url: string;

  constructor(title: string, detail: string, url: string) {
    this.title = title;
    this.detail = detail;
    this.url = url;
  }
}

export class AboutExplanation {
  id: string;
  title: string;
  summary: string;
  detail: string;

  constructor(id: string, title: string, summary: string, detail: string) {
    this.id = id;
    this.title = title;
    this.summary = summary;
    this.detail = detail;
  }
}

export class PolicySection {
  title: string;
  items: string[];

  constructor(title: string, items: string[]) {
    this.title = title;
    this.items = items;
  }
}

export class AboutContent {
  static readonly APP_NAME: string = 'HITA NEXT';
  static readonly TAGLINE: string = '为哈工大学生打造的第三方课表与学习管理工具';

  static readonly PRIVACY_POLICY_URL: string =
    'https://agreement-drcn.hispace.dbankcloud.cn/index.html?lang=zh&agreementId=2056866492535841728';

  static contributors(): AboutContributor[] {
    return [
      new AboutContributor('蒋国贤', 'samerberry', $r('app.media.avatar_samerberry'),
        'https://github.com/samerberry'),
      new AboutContributor('刘震宇', 'sofa1145', $r('app.media.avatar_shafa1145'),
        'https://github.com/sofa1145'),
      new AboutContributor('肖丁荣', 'xdInternet', $r('app.media.avatar_xdinternet'),
        'https://github.com/xdInternet')
    ];
  }

  static projectCredits(): AboutCredit[] {
    return [
      new AboutCredit('HITA_X', '最初的 Android 项目，MIT License', 'https://github.com/StupidTrees/HITA_X'),
      new AboutCredit('HITA Android', '功能逻辑与数据结构参考', 'https://github.com/HIT-A/HITA_Android'),
      new AboutCredit('HITA Aura', 'iOS 端界面布局与交互参考', 'https://github.com/HIT-A/HITA-Aura')
    ];
  }

  static explanations(): AboutExplanation[] {
    return [
      new AboutExplanation('identity', '应用身份', '开发与维护主体',
        'HITA NEXT 由独立开发者维护。本应用不是哈尔滨工业大学官方应用。'),
      new AboutExplanation('authentication', '校方网页', '账号使用与会话管理',
        '您可从「更多」进入「导入数据」，选择校区并点击「重新导入」打开校方网页。请使用本人账号，仅在校方网页按提示填写账号、密码或验证码。' +
        '应用在本机保存校方返回的会话。您可通过同一入口选择校区并点击「删除数据」，移除所选校区的会话及账号资料。'),
      new AboutExplanation('data', '教务数据', '数据来源与用途',
        '应用从所选校区的教务系统读取课表、考试、成绩等信息。应用内的编辑仅影响本地记录，不会修改校方教务数据。' +
        '课程、考试和成绩以校方教务系统为准。手动管理课表、导入 ICS 日历和记录学习待办可独立使用。')
    ];
  }

  static readonly POLICY_TITLE: string = '关于HITA NEXT与隐私的声明';
  static readonly POLICY_UPDATED: string = '2026.10.8';
  static readonly POLICY_EFFECTIVE: string = '2026.10.8';
  static readonly CONTACT_EMAIL: string = 'jiangguoxian0313@outlook.com';

  static policyIntro(): string[] {
    return [
      'HITA NEXT 是由 蒋国贤 （以下简称“我们”）独立开发和维护的鸿蒙课表与学习管理应用。' +
        '本隐私声明由我们为处理您的个人信息而制定。',
      '我们非常重视您的个人信息和隐私保护，将会按照法律要求和业界成熟的安全标准，为您的个人信息提供相应的安全保护措施。'
    ];
  }

  static policy(): PolicySection[] {
    return [
      new PolicySection('1. 我们如何收集和使用您的个人信息', [
        '我们仅在有合法性基础的情形下才会使用您的个人信息。根据适用的法律，我们可能会基于您的同意、为履行/订立您与我们的合同所必需、' +
          '履行法定义务所必需等合法性基础，使用您的个人信息。',
        '1.1 我们提供下列服务时会处理必要的个人信息。',
        '您选择使用教务功能时，应用内会打开所选校区的校方网页。网页要求填写的账号、密码或验证码由校方接收和处理。' +
          '应用在本机保存校方返回的会话凭据（如 Cookie）及相关教务账号资料，用于读取教务数据和展示账号信息。',
        '应用使用该会话向所选校区的教务系统读取数据，用于导入课表、查询考试、成绩、学分和空教室。' +
          '导入的课程及考试安排保存在本机。教务会话失效时，应用可能使用已有网页会话尝试续期。',
        '为了实现应用功能，在获取您的同意后我们需要收集您的日历 。'
      ]),
      new PolicySection('2. 设备权限调用', [
        '本服务在运行过程中需要使用以下权限，我们会在使用之前征求您的意见，任何未明确同意使用的权限，均不会被随意调用。',
        '日历（读取日历信息、添加、移除或更改日历活动）',
        '当您在课表工具中使用”导出至手机日历“功能时，我们会在日历中添加对应的课程活动',
        '您可以随时访问系统“设置”来管理本服务的权限。'
      ]),
      // 托管页这一节的编号和“前往……”的具体位置为空，这里只保留有内容的句子。
      new PolicySection('3. 管理您的个人信息', [
        '3.1 信息访问',
        '3.2 信息更正：当您需要更新您的个人信息，或发现我们处理您的个人信息有误时，您有权作出更正或更新。',
        '3.3 信息删除',
        '3.4 撤销同意：您可通过「更多」顶部入口选择校区并点击「删除数据」，移除该校区在应用中保存的会话及相关账号资料。' +
          '您可在课表管理中单独删除已导入的课表。',
        '3.5 注销服务：在注销账户之后，我们将停止为您提供产品或服务，并依据您的要求，删除您的个人信息，法律法规另有规定的除外。',
        '如您对您的数据主体权利有进一步要求或存在任何疑问、意见或建议，可通过本声明中“如何联系我们”章节中所述方式与我们取得联系，' +
          '并行使您的相关权利。'
      ]),
      new PolicySection('4. 信息存储地点及期限', [
        '4.1 我们承诺，除法律法规另有规定外，我们对您的信息的保存期限应当为实现处理目的所必要的最短时间。',
        '4.2 校方网页操作及教务查询请求发送至所选校区的服务系统。应用保存的教务会话、账号资料及已导入的课表数据存储在您的设备上。'
      ]),
      new PolicySection('5. 如何联系我们', [
        '您可通过以下方式联系我们，并行使您的相关权利，我们会尽快回复。',
        '邮箱：' + AboutContent.CONTACT_EMAIL,
        '如果您对我们的回复不满意, 特别是当个人信息处理行为损害了您的合法权益时您还可以通过向有管辖权的人民法院提起诉讼、' +
          '向行业自律协会或政府相关管理机构投诉等外部途径进行解决。 您也可以向我们了解可能适用的相关投诉途径的信息。'
      ])
    ];
  }
}
