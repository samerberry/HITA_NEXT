import { ScheduleChangeSignal } from '../../../common/util/ScheduleChangeSignal';
/** Persists whether the user wants class-start notifications. */
import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const STORE_NAME: string = 'hitanext_store';
const ENABLED_KEY: string = 'class_reminder_enabled';
const LEAD_MINUTES_KEY: string = 'class_reminder_lead_minutes';
const NOTIFIED_KEY: string = 'class_reminder_notified';
const PLANS_KEY: string = 'class_reminder_plans';
const SIGNATURE_KEY: string = 'class_reminder_signature';

export class ClassReminderPlan {
  type: string = 'CLASS';
  timetableId: string = '';
  id: string = '';
  name: string = '';
  place: string = '';
  subjectId: string = '';
  from: number = 0;
  to: number = 0;
}

export class ClassReminderStore {
  private static instance: ClassReminderStore | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;

  static getInstance(): ClassReminderStore {
    if (ClassReminderStore.instance === undefined) {
      ClassReminderStore.instance = new ClassReminderStore();
    }
    return ClassReminderStore.instance;
  }

  async init(context: common.Context): Promise<void> {
    if (this.store !== undefined) {
      return;
    }
    try {
      this.store = await preferences.getPreferences(context, { name: STORE_NAME });
    } catch (e) {
      this.store = undefined;
    }
  }

  async loadEnabled(strict: boolean = false): Promise<boolean> {
    if (this.store === undefined) {
      if (strict) throw new Error('提醒设置暂时无法读取');
      return false;
    }
    try {
      return Boolean(await this.store.get(ENABLED_KEY, false));
    } catch (e) {
      if (strict) throw new Error('提醒设置暂时无法读取');
      return false;
    }
  }

  async saveEnabled(enabled: boolean): Promise<void> {
    if (this.store === undefined) throw new Error('提醒设置暂时无法保存');
    await this.store.put(ENABLED_KEY, enabled);
    await this.store.flush();
    ScheduleChangeSignal.notify();
  }

  static validLeadMinutes(value: number): boolean {
    return Number.isInteger(value) && value >= 1 && value <= 120;
  }

  async loadLeadMinutes(strict: boolean = false): Promise<number> {
    if (this.store === undefined) {
      if (strict) throw new Error('提醒设置暂时无法读取');
      return 15;
    }
    try {
      const value: number = Number(await this.store.get(LEAD_MINUTES_KEY, 15));
      return ClassReminderStore.validLeadMinutes(value) ? value : 15;
    } catch (_) {
      if (strict) throw new Error('提醒设置暂时无法读取');
      return 15;
    }
  }

  async saveLeadMinutes(value: number): Promise<void> {
    if (!ClassReminderStore.validLeadMinutes(value)) throw new Error('请输入 1–120 的整数');
    if (this.store === undefined) throw new Error('提醒设置暂时无法保存');
    await this.store.put(LEAD_MINUTES_KEY, value);
    await this.store.flush();
    ScheduleChangeSignal.notify();
  }

  async loadExamEnabled(): Promise<boolean> {
    return this.store !== undefined && Boolean(await this.store.get('exam_reminder_enabled', false));
  }

  async saveExamEnabled(enabled: boolean): Promise<void> {
    if (this.store === undefined) throw new Error('提醒设置暂时无法保存');
    await this.store.put('exam_reminder_enabled', enabled);
    await this.store.flush();
    ScheduleChangeSignal.notify();
  }

  async loadExamLeadMinutes(): Promise<number> {
    const value: number = this.store === undefined ? 60 : Number(await this.store.get('exam_reminder_lead_minutes', 60));
    return ClassReminderStore.validLeadMinutes(value) ? value : 60;
  }

  async saveExamLeadMinutes(minutes: number): Promise<void> {
    if (!ClassReminderStore.validLeadMinutes(minutes) || this.store === undefined) throw new Error('提醒时间无效');
    await this.store.put('exam_reminder_lead_minutes', minutes);
    await this.store.flush();
    ScheduleChangeSignal.notify();
  }

  async hasNotified(key: string): Promise<boolean> {
    const keys: string[] = await this.loadNotified();
    return keys.indexOf(key) >= 0;
  }

  async markNotified(key: string): Promise<void> {
    const keys: string[] = await this.loadNotified();
    if (keys.indexOf(key) >= 0) {
      return;
    }
    keys.push(key);
    await this.saveNotified(keys);
  }

  async clearNotified(): Promise<void> {
    await this.saveNotified([]);
  }

  async loadSignature(): Promise<string> {
    if (this.store === undefined) {
      return '';
    }
    try {
      return String(await this.store.get(SIGNATURE_KEY, ''));
    } catch (e) {
      return '';
    }
  }

  async saveSignature(signature: string): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      await this.store.put(SIGNATURE_KEY, signature);
      await this.store.flush();
    } catch (e) {
    }
  }

  async loadPlans(): Promise<ClassReminderPlan[]> {
    if (this.store === undefined) {
      return [];
    }
    try {
      const raw: string = String(await this.store.get(PLANS_KEY, '[]'));
      const parsed: Object[] = JSON.parse(raw) as Object[];
      if (parsed === undefined || parsed === null) {
        return [];
      }
      const out: ClassReminderPlan[] = [];
      for (let i: number = 0; i < parsed.length; i++) {
        const row: Record<string, string | number> = parsed[i] as Record<string, string | number>;
        const plan: ClassReminderPlan = new ClassReminderPlan();
        plan.type = row['type'] === 'EXAM' ? 'EXAM' : 'CLASS';
        plan.timetableId = typeof row['timetableId'] === 'string' ? String(row['timetableId']) : '';
        plan.id = String(row['id']);
        plan.name = String(row['name']);
        plan.place = String(row['place']);
        plan.subjectId = String(row['subjectId']);
        plan.from = Number(row['from']);
        plan.to = Number(row['to']);
        if (plan.id.length > 0 && plan.from > 0) {
          out.push(plan);
        }
      }
      return out;
    } catch (e) {
      return [];
    }
  }

  async savePlans(plans: ClassReminderPlan[]): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      await this.store.put(PLANS_KEY, JSON.stringify(plans));
      await this.store.flush();
    } catch (e) {
    }
  }

  private async loadNotified(): Promise<string[]> {
    if (this.store === undefined) {
      return [];
    }
    try {
      const raw: string = String(await this.store.get(NOTIFIED_KEY, ''));
      if (raw.length === 0) {
        return [];
      }
      return raw.split('|');
    } catch (e) {
      return [];
    }
  }

  private async saveNotified(keys: string[]): Promise<void> {
    if (this.store === undefined) {
      return;
    }
    try {
      await this.store.put(NOTIFIED_KEY, keys.join('|'));
      await this.store.flush();
    } catch (e) {
    }
  }
}
