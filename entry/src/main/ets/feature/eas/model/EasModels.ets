/**
 * EasModels.ets — EAS 数据模型（HITA_X data/model/eas/*.kt 直迁 + 新版字段合并）。
 *
 * 出处：
 *  - HITA_X: data/model/eas/CourseScoreItem.kt / TermItem.kt / ExamItem.kt / CourseItem.kt
 *  - 新版(深圳 JSON): decomp .../data/source/web/eas/ShenzhenWebScoreParser.java（字段映射见解析器）
 *
 * 说明：HITA_X CourseScoreItem.credits 原为 Int，新版 'xf' 为数值（可小数），
 * 统一为 number；成绩展示以 finalScoresText 优先（可承载 "优秀"/"95"），
 * finalScores 为可解析的整数值，解析失败置 -1（对齐 ShenzhenWebScoreParser）。
 */

/** 学年学期（TermItem.kt 直迁；name = yearName + termName）。 */
export class EasTermItem {
  yearCode: string = '';
  yearName: string = '';
  termCode: string = '';
  termName: string = '';
  isCurrent: boolean = false;

  get name(): string {
    return this.yearName + this.termName;
  }

  getCode(): string {
    return this.yearCode + this.termCode;
  }

  equalsKey(other: EasTermItem | undefined): boolean {
    if (other === undefined || other === null) {
      return false;
    }
    return this.yearCode === other.yearCode && this.termCode === other.termCode;
  }
}

/** 成绩条目（合并 HITA_X 与新版字段）。 */
export class EasCourseScoreItem {
  /** 最终成绩文本（"95"/"优秀"/"通过"…），展示优先。 */
  finalScoresText: string = '';
  /** 可解析的整数成绩；无文本或不可解析时 -1（新版 parser 语义）。 */
  finalScores: number = -1;
  /** 学分（新版 'xf'，可小数；HITA_X 原 Int 已放宽）。 */
  credits: number = 0;
  /** 学时（新版 'xs'）。 */
  hours: number = 0;
  courseName: string = '';
  courseCode: string = '';
  /** 课程性质（新版 kcxz / kcxzen 二选一）。 */
  courseProperty: string = '';
  /** 课程类别（新版 kclb / kclben 二选一）。 */
  courseCategory: string = '';
  schoolName: string = '';
  assessMethod: string = '';
  termName: string = '';

  /** 成绩展示文本。 */
  displayScore(): string {
    if (this.finalScoresText.length > 0) {
      return this.finalScoresText;
    }
    if (this.finalScores >= 0) {
      return this.finalScores.toString();
    }
    return '—';
  }
}

/** 考试条目（ExamItem.kt 直迁）。 */
export class EasExamItem {
  courseCode: string = '';
  courseName: string = '';
  examDate: string = '';
  examTime: string = '';
  /** 期中/期末等。 */
  examType: string = '';
  examLocation: string = '';
  termName: string = '';
  campusName: string = '';
}

/** 教务课程条目（CourseItem.kt：课表导入用）。 */
export class EasCourseItem {
  /** 课程代码（深圳新版 JSON 课表会直接返回；旧 HTML 可为空）。 */
  code: string = '';
  name: string = '';
  rawName: string = '';
  weekNumbers: number[] = [];
  startTime: string = '';
  endTime: string = '';
  /** 电子实验中心提供的实际上课日期，不依赖推算学期周次。 */
  scheduledDate: string = '';
  /** 周次列表（如 [1,2,3,5-8]，按导入源形态）。 */
  weeks: string = '';
  teacher: string = '';
  classroom: string = '';
  /** 课程性质（kcxz/kcxzmc，例如“必修”“限选”“任选”）。 */
  courseProperty: string = '';
  /** 课程类别或选课类别（kclb/kclbmc/xkfsmc 等）。 */
  courseCategory: string = '';
  /** 考核方式（khfs/khfsmc/是否考试课等）。 */
  assessMethod: string = '';
  /** 选课方式编码或名称（xkfsdm/xkfsmc/rwlxmc 等）。 */
  selectionCategory: string = '';
  /** 学分；未知时为 0。 */
  credit: number = 0;
  /** 星期几 1..7。 */
  dayOfWeek: number = 0;
  /** 起始节次。 */
  beginSection: number = 0;
  /** 持续节次。 */
  sectionCount: number = 0;
}
