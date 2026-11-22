import { LearningTask, LearningTaskKind, LearningTaskRules } from '../../common/model/learning/LearningTask';
import { EasEventItem, EasEventType } from '../../common/model/timetable/TimetableModels';
import { NextClassModel } from './NextClassModel';

export enum WidgetTab { COURSE, EXAM, TASK }

/** Only launcher-visible details, never a serialized database row or task note. */
class AgendaItem {
  id: string = '';
  title: string = '';
  detail: string = '';
  from: number = 0;
  to: number = 0;
  allDay: boolean = false;
}

export class AgendaRow {
  id: string = '';
  title: string = '';
  detail: string = '';
  when: string = '';
  status: string = '';
}

export class AgendaView {
  rows: AgendaRow[] = [];
  message: string = '';
  hint: string = '';
  nextChange: number = 0;
}

export class WidgetAgenda {
  static exams(events: EasEventItem[], now: number): string {
    const items: AgendaItem[] = events.filter(event => event.type === EasEventType.EXAM &&
      Number.isFinite(event.from) && Number.isFinite(event.to) && event.to > now && event.to > event.from)
      .sort((a, b) => a.from - b.from || a.id.localeCompare(b.id)).slice(0, 16)
      .map((event: EasEventItem): AgendaItem => {
        const item = new AgendaItem();
        item.id = event.id;
        item.title = NextClassModel.label(event.name, '未命名考试');
        item.detail = NextClassModel.label(event.place, '考场待定');
        item.from = event.from;
        item.to = event.to;
        return item;
      });
    return JSON.stringify(items);
  }

  static tasks(tasks: LearningTask[]): string {
    // Effective deadlines keep all-day work actionable until the end of its local day.
    const items: AgendaItem[] = tasks.filter(task => task.completedAt === 0).sort(LearningTaskRules.compareDeadlines)
      .map((task: LearningTask): AgendaItem => {
        const item = new AgendaItem();
        item.id = task.id;
        item.title = NextClassModel.label(task.title, '未命名待办');
        const review = task.kind === LearningTaskKind.REVIEW;
        const subject = NextClassModel.label(review ? task.examName : task.courseName, '');
        item.detail = (review ? '复习' : '作业') + (subject ? ' · ' + subject : '');
        item.from = task.dueAt;
        item.to = LearningTaskRules.deadline(task);
        item.allDay = task.allDay;
        return item;
      });
    return JSON.stringify(items);
  }

  static view(tab: WidgetTab, json: string, loading: boolean, now: number): AgendaView {
    const view = new AgendaView();
    const tomorrow = new Date(now);
    tomorrow.setHours(24, 0, 0, 0);
    view.nextChange = tomorrow.getTime();
    const exam = tab === WidgetTab.EXAM;
    const section = exam ? '考试' : '待办';
    if (loading) {
      view.message = '正在读取' + section;
      return view;
    }
    try {
      const items = JSON.parse(json) as AgendaItem[];
      if (!Array.isArray(items)) throw new Error('Invalid agenda');
      for (const item of items) {
        if (exam && item.to <= now) continue;
        const row = new AgendaRow();
        row.id = item.id;
        row.title = item.title;
        row.detail = item.detail;
        if (exam) {
          row.status = item.from <= now ? '正在考试' : '即将考试';
          row.when = NextClassModel.timeLabel(item.from, item.to, now);
          view.nextChange = Math.min(view.nextChange, item.from > now ? item.from : item.to);
        } else {
          const date = NextClassModel.dateLabel(item.from, now);
          row.status = item.from === 0 ? '待安排' : (item.to < now ? '已逾期' :
            (date === '今天' ? '今天截止' : '待完成'));
          row.when = item.from === 0 ? '未设截止时间' :
            (item.allDay ? date + ' 全天' : NextClassModel.startLabel(item.from, now)) + ' 截止';
          if (item.to >= now) view.nextChange = Math.min(view.nextChange, item.to + 1);
        }
        view.rows.push(row);
        if (exam && view.rows.length === 2) break;
      }
      if (view.rows.length === 0) {
        view.message = exam ? '暂无近期考试' : '没有未完成待办';
        view.hint = exam ? '已保存的考试会显示在这里' : '新建的作业和复习会显示在这里';
      }
    } catch (_) {
      view.rows = [];
      view.message = section + '暂不可用';
      view.hint = '打开应用后重试';
    }
    return view;
  }
}
