import { HitaDesign } from '../../common/theme/HitaDesign';
/**
 * 关于页与隐私政策的全部文案。改名单、致谢或政策条款时只改这里，页面只负责排版。
 * 隐私政策正文与华为协议托管服务上的版本保持一致（见 PRIVACY_POLICY_URL）。
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
  static readonly TAGLINE: string = '哈工大一校三区的鸿蒙课表与教务助手';
  static readonly DISCLAIMER: string = '本应用不是哈尔滨工业大学官方应用。';

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

  static readonly POLICY_TITLE: string = '关于HITA NEXT与隐私的声明';
  static readonly POLICY_UPDATED: string = '2026.10.8';
  static readonly POLICY_EFFECTIVE: string = '2026.10.8';
  static readonly CONTACT_EMAIL: string = 'jiangguoxian0313@outlook.com';

  static policyIntro(): string[] {
    return [
      'HITA NEXT 是由 蒋国贤 （以下简称“我们”）为您提供的，用于哈工大一校三区学生课表查看，教务登录，本地学业信息管理的应用。' +
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
        '我们为您提供下述课表查看，教务登录，本地学习信息管理课表查看，教务登录，本地学习信息管理功能在您使用相关业务的过程中，' +
          '我们会处理所必需的信息，以便履行我们的合同义务若您不提供相关信息，会影响到您使用本应用的相关功能/服务。',
        '为了实现应用功能，在获取您的同意后我们需要收集您的教务系统登录凭证（仅用于课表与成绩查询，存储在您的设备本地）,' +
          '课表，课程，考试等数据（来自教务系统，存储于本地，打开应用时会自动刷新） 。',
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
        '3.4 撤销同意',
        '3.5 注销服务：在注销账户之后，我们将停止为您提供产品或服务，并依据您的要求，删除您的个人信息，法律法规另有规定的除外。',
        '如您对您的数据主体权利有进一步要求或存在任何疑问、意见或建议，可通过本声明中“如何联系我们”章节中所述方式与我们取得联系，' +
          '并行使您的相关权利。'
      ]),
      new PolicySection('4. 信息存储地点及期限', [
        '4.1 我们承诺，除法律法规另有规定外，我们对您的信息的保存期限应当为实现处理目的所必要的最短时间。',
        '4.2 上述信息将会传输并保存至中国境内的服务器。'
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
