import { CalendarSyncStore } from './CalendarSyncStore';
import { ReminderEventSelection } from './ReminderEventSelection';
/**
 * Class reminders fire via notificationManager while HITA is in foreground or
 * still running in the background. They are not registered with the system agent.
 */
import { common, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { EasEventItem, EasEventType } from '../../../common/model/timetable/TimetableModels';
import { EasTimeTools } from '../../../common/util/EasTimeTools';
import { ClassReminderPlan, ClassReminderStore } from './ClassReminderStore';

const SLOT: notificationManager.SlotType = notificationManager.SlotType.SOCIAL_COMMUNICATION;
const DOMAIN: number = 0x0000;
const TAG: string = 'ClassReminder';

export class ClassReminderSyncResult {
  scheduled: number = 0;
  pendingClasses: number = 0;
  duePublished: number = 0;
  nextFire: string = '';
  error: string = '';
}

export class ClassReminderScheduler {
  private static dispatching: boolean = false;
  private static syncSeq: number = 0;
  private static slotReady: boolean = false;

  static async requestNotification(context: common.UIAbilityContext): Promise<boolean> {
    try {
      if (!(await notificationManager.isNotificationEnabled())) {
        await notificationManager.requestEnableNotification(context);
      }
    } catch (e) {
      ClassReminderScheduler.logError('requestEnableNotification', e);
    }
    await ClassReminderScheduler.ensureSlot();
    try {
      return await notificationManager.isNotificationEnabled();
    } catch (e) {
      ClassReminderScheduler.logError('isNotificationEnabled', e);
      return false;
    }
  }

  static async cancelAll(_context?: common.UIAbilityContext): Promise<void> {
    const store: ClassReminderStore = ClassReminderStore.getInstance();
    await store.clearNotified();
    await store.savePlans([]);
    await store.saveSignature('');
  }

  static async restore(context: common.UIAbilityContext): Promise<void> {
    const store: ClassReminderStore = ClassReminderStore.getInstance();
    if (!(await store.loadEnabled()) && !(await store.loadExamEnabled())) {
      return;
    }
    await ClassReminderScheduler.ensureSlot();
    const events: EasEventItem[] = ClassReminderScheduler.eventsFromPlans(await store.loadPlans());
    if (events.length === 0) {
      return;
    }
    await ClassReminderScheduler.dispatchDue(context, events);
  }

  static async sync(context: common.UIAbilityContext, events: EasEventItem[],
    force: boolean = false): Promise<ClassReminderSyncResult> {
    const result: ClassReminderSyncResult = new ClassReminderSyncResult();
    const upcoming: EasEventItem[] = ClassReminderScheduler.upcomingClasses(events);
    result.pendingClasses = upcoming.length;
    result.scheduled = upcoming.length;
    const store: ClassReminderStore = ClassReminderStore.getInstance();
    const leadMinutes: number = await store.loadLeadMinutes();
    const signature: string = leadMinutes.toString() + ':' + (await store.loadExamLeadMinutes()).toString() + ':' +
      (await store.loadEnabled()).toString() + ':' + (await store.loadExamEnabled()).toString() + ':' +
      ClassReminderScheduler.signatureOf(upcoming);
    if (!force && signature.length > 0 && signature === await store.loadSignature()) {
      result.duePublished = await ClassReminderScheduler.dispatchDue(context, upcoming);
      if (upcoming.length > 0) {
        result.nextFire = ClassReminderScheduler.nextFireText(upcoming[0], leadMinutes);
      }
      return result;
    }
    const seq: number = ++ClassReminderScheduler.syncSeq;
    await ClassReminderScheduler.ensureSlot();
    if (seq !== ClassReminderScheduler.syncSeq) {
      return result;
    }
    await store.savePlans(ClassReminderScheduler.plansFromEvents(upcoming));
    if (upcoming.length > 0) {
      result.nextFire = ClassReminderScheduler.nextFireText(upcoming[0], leadMinutes);
    }
    result.duePublished = await ClassReminderScheduler.dispatchDue(context, upcoming);
    if (seq === ClassReminderScheduler.syncSeq) {
      await store.saveSignature(signature);
    }
    hilog.info(DOMAIN, TAG,
      'sync pending=%{public}d due=%{public}d',
      result.pendingClasses, result.duePublished);
    return result;
  }

  static async dispatchDue(context: common.UIAbilityContext, events: EasEventItem[]): Promise<number> {
    if (ClassReminderScheduler.dispatching) return 0;
    ClassReminderScheduler.dispatching = true;
    try { return await ClassReminderScheduler.dispatch(context, events); }
    finally { ClassReminderScheduler.dispatching = false; }
  }

  private static async dispatch(context: common.UIAbilityContext, events: EasEventItem[]): Promise<number> {
    const store: ClassReminderStore = ClassReminderStore.getInstance();
    const classes: boolean = await store.loadEnabled();
    const exams: boolean = await store.loadExamEnabled();
    if (!classes && !exams) return 0;
    const classMinutes: number = await store.loadLeadMinutes();
    const examMinutes: number = await store.loadExamLeadMinutes();
    const upcoming: EasEventItem[] = ClassReminderScheduler.upcomingClasses(events);
    let published: number = 0;
    for (let i: number = 0; i < upcoming.length; i++) {
      const event: EasEventItem = upcoming[i];
      const exam: boolean = event.type === EasEventType.EXAM;
      if (exam ? !exams : !classes) continue;
      const leadMinutes: number = exam ? examMinutes : classMinutes;
      if (await CalendarSyncStore.getInstance().covers(event.timetableId, event.id, event.from, leadMinutes)) continue;
      if (event.from - Date.now() > leadMinutes * 60000) {
        continue;
      }
      const key: string = ClassReminderScheduler.notifyKey(event);
      if (await store.hasNotified(key) || (event.type === EasEventType.CLASS &&
        await store.hasNotified(event.id + ':' + event.from.toString()))) {
        continue;
      }
      const text: [string, string] = ClassReminderScheduler.copyText(event);
      const alertErr: string = await ClassReminderScheduler.publishAlert(text[0], text[1],
        ClassReminderScheduler.hashId('alert:' + event.id + ':' + event.from.toString()), context, event);
      if (alertErr.length === 0) {
        await ClassReminderStore.getInstance().markNotified(key);
        published++;
      }
    }
    return published;
  }

  private static upcomingClasses(events: EasEventItem[]): EasEventItem[] {
    return ReminderEventSelection.blocks(events).filter((event: EasEventItem): boolean => event.from > Date.now());
  }

  private static signatureOf(upcoming: EasEventItem[]): string {
    let text: string = '';
    for (let i: number = 0; i < upcoming.length; i++) {
      text += JSON.stringify([upcoming[i].id, upcoming[i].from.toString(), upcoming[i].to.toString(),
        upcoming[i].name, upcoming[i].place, upcoming[i].type]) + ';';
    }
    return text;
  }

  private static notifyKey(event: EasEventItem): string {
    return event.type + ':' + event.id + ':' + event.from.toString();
  }

  private static copyText(event: EasEventItem): [string, string] {
    const place: string = event.place.length > 0 ? event.place : '地点待定';
    const title: string = event.name.length > 0 && event.name !== 'NULL' ? event.name : '课程提醒';
    const minutes: number = Math.max(1, Math.ceil((event.from - Date.now()) / 60000));
    const content: string = minutes.toString() + (event.type === EasEventType.EXAM ? '分钟后考试 · ' : '分钟后上课 · ') +
      EasTimeTools.printTime(event.from) + ' · ' + place;
    return [title, content];
  }

  private static plansFromEvents(events: EasEventItem[]): ClassReminderPlan[] {
    const plans: ClassReminderPlan[] = [];
    for (let i: number = 0; i < events.length; i++) {
      const plan: ClassReminderPlan = new ClassReminderPlan();
      plan.type = events[i].type;
      plan.timetableId = events[i].timetableId;
      plan.id = events[i].id;
      plan.name = events[i].name;
      plan.place = events[i].place;
      plan.subjectId = events[i].subjectId;
      plan.from = events[i].from;
      plan.to = events[i].to;
      plans.push(plan);
    }
    return plans;
  }

  private static eventsFromPlans(plans: ClassReminderPlan[]): EasEventItem[] {
    const events: EasEventItem[] = [];
    for (let i: number = 0; i < plans.length; i++) {
      const event: EasEventItem = new EasEventItem();
      event.id = plans[i].id;
      event.type = plans[i].type === 'EXAM' ? EasEventType.EXAM : EasEventType.CLASS;
      event.timetableId = plans[i].timetableId;
      event.name = plans[i].name;
      event.place = plans[i].place;
      event.subjectId = plans[i].subjectId;
      event.from = plans[i].from;
      event.to = plans[i].to;
      events.push(event);
    }
    return events;
  }

  private static async publishAlert(title: string, text: string, id: number,
    context: common.UIAbilityContext, event: EasEventItem): Promise<string> {
    await ClassReminderScheduler.ensureSlot();
    try {
      const request: notificationManager.NotificationRequest = {
        id: id,
        notificationSlotType: SLOT,
        tapDismissed: true,
        isAlertOnce: false,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            title: title,
            text: text
          }
        }
      };
      if (context.abilityInfo !== undefined) {
        request.wantAgent = await wantAgent.getWantAgent({
          wants: [{ bundleName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name,
            parameters: { hitaReminderEventId: event.id, hitaReminderTimetableId: event.timetableId } }],
          operationType: wantAgent.OperationType.START_ABILITY,
          requestCode: id,
          wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
        });
      }
      await notificationManager.publish(request);
      return '';
    } catch (e) {
      ClassReminderScheduler.logError('publishAlert ' + title, e);
      return ClassReminderScheduler.errorText(e);
    }
  }

  private static nextFireText(event: EasEventItem, leadMinutes: number): string {
    const remindAt: number = event.from - leadMinutes * 60 * 1000;
    const when: Date = new Date(remindAt > Date.now() ? remindAt : Date.now());
    const hour: number = when.getHours();
    const minute: number = when.getMinutes();
    const hh: string = hour < 10 ? '0' + hour.toString() : hour.toString();
    const mm: string = minute < 10 ? '0' + minute.toString() : minute.toString();
    return hh + ':' + mm;
  }

  private static async ensureSlot(): Promise<void> {
    if (ClassReminderScheduler.slotReady) {
      return;
    }
    try {
      await notificationManager.addSlot(SLOT);
    } catch (e) {
      ClassReminderScheduler.logError('addSlot', e);
    }
    ClassReminderScheduler.slotReady = true;
  }

  private static hashId(id: string): number {
    let hash: number = 0;
    for (let i: number = 0; i < id.length; i++) {
      hash = (hash * 31 + id.charCodeAt(i)) | 0;
    }
    const positive: number = hash < 0 ? -hash : hash;
    return (positive % 1000000000) + 2000;
  }

  private static errorText(e: Object): string {
    try {
      const err: BusinessError = e as BusinessError;
      return String(err.code) + ' ' + err.message;
    } catch (ignored) {
      return String(e);
    }
  }

  private static logError(where: string, e: Object): void {
    hilog.error(DOMAIN, TAG, '%{public}s %{public}s', where, ClassReminderScheduler.errorText(e));
  }
}
