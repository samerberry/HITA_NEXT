/** Only known, actionable failures may be shown to users. */
export class EasUserMessages {
  static fromError(message: string, fallback: string): string {
    switch (message.trim()) {
      case '教务会话已失效，请重新登录':
      case '深圳教务会话已失效，请重新登录':
      case '返回的不是课表页，请重新登录后再试':
        return '教务登录已过期，请重新登录后重试';
      case '教务系统拒绝访问':
        return '教务系统拒绝了访问，请稍后重试，必要时重新登录';
      case '本部研究生课表接口暂未接入':
      case '暂不支持导入本部研究生课表':
        return '暂不支持导入本部研究生课表';
      case '当前校区暂不支持成绩查询':
        return '当前校区暂不支持成绩查询，请到学校教务网站查看';
      case '当前校区暂不支持考试查询，请手动添加考试':
        return '当前校区暂不支持考试查询，请手动添加考试';
      case '本部和威海研究生考试接口暂未接入，请到教务网站查询':
        return message.trim();
      case '考试页面无法识别，请稍后重试':
      case '教务考试查询暂不可用，请稍后重试':
        return '暂时无法读取教务考试安排，请稍后重试或到教务网站核对';
      case '未获取到学期列表':
      case '未获取到深圳学期列表':
        return '未获取到学期信息，请稍后重试';
      case '未获取到考试安排':
        return '暂时无法获取考试安排，请稍后重试或手动添加';
      case '课表请求网络失败':
      case '学期请求网络失败':
      case '成绩请求网络失败':
      case '考试请求网络失败':
        return '无法连接教务系统，请检查网络后重试';
      case '课表解析为空，请检查该学期是否已有课表':
      case '深圳课表解析为空，请检查该学期是否已有课表':
        return '未获取到课程，请确认所选学期是否已有课表';
      case '课表页返回异常，未找到课表表格':
      case '课表已获取，但课程节次无法解析':
        return '暂时无法读取课表，请稍后重试';
      case '本地课表数据库写入失败，请重试':
      case '课表已解析，但本地没有写入任何课次':
        return '课表保存失败，请重试';
      default:
        // Never display raw server responses, internal paths or database errors.
        return fallback;
    }
  }
}
