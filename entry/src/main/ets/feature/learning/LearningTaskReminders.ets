import { common, wantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { RdbHelper } from '../../common/db/RdbHelper';
import { LearningTask, LearningTaskRules } from '../../common/model/learning/LearningTask';
import { EasTimeTools } from '../../common/util/EasTimeTools';

/** Uses the existing in-process reminder loop; no promise of delivery after process termination. */
export class LearningTaskReminders {
  private static published: Map<string, number> = new Map<string, number>();

  static id(taskId: string): number {
    let hash: number = 0;
    for (let index: number = 0; index < taskId.length; index++) hash = (hash * 31 + taskId.charCodeAt(index)) | 0;
    return 1100000000 + (Math.abs(hash) % 900000000);
  }

  static async cancel(taskId: string): Promise<void> {
    try { await notificationManager.cancel(LearningTaskReminders.id(taskId)); } catch (_) {}
    LearningTaskReminders.published.delete(taskId);
  }

  static async refresh(context: common.UIAbilityContext): Promise<void> {
    const rdb: RdbHelper = RdbHelper.getInstance();
    const tasks: LearningTask[] = await rdb.getLearningTasks();
    for (const id of Array.from(LearningTaskReminders.published.keys())) {
      if (!tasks.some(task => task.id === id && task.completedAt === 0 &&
        task.remindAt === LearningTaskReminders.published.get(id))) {
        await LearningTaskReminders.cancel(id);
      }
    }
    if (!(await notificationManager.isNotificationEnabled())) return;
    for (const task of tasks) {
      if (!LearningTaskRules.reminderDue(task, Date.now())) continue;
      try {
        // A completion/delete during asynchronous notification setup must not resurrect an alert.
        const current: LearningTask | undefined = (await rdb.getLearningTasks()).find(item => item.id === task.id);
        if (current === undefined || current.remindAt !== task.remindAt || !LearningTaskRules.reminderDue(current, Date.now())) continue;
        const id: number = LearningTaskReminders.id(task.id);
        const agent = await wantAgent.getWantAgent({
          wants: [{ bundleName: context.abilityInfo.bundleName, abilityName: context.abilityInfo.name,
            parameters: { hitaLearningTaskId: task.id } }],
          operationType: wantAgent.OperationType.START_ABILITY, requestCode: id,
          wantAgentFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
        });
        await notificationManager.publish({
          id: id, notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
          tapDismissed: true, isAlertOnce: true, wantAgent: agent,
          content: { notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
            normal: { title: task.title, text: (task.kind === 'REVIEW' ? task.examName : task.courseName) +
              (task.dueAt > 0 ? ' · 截止 ' + EasTimeTools.printDate(task.dueAt) +
                (task.allDay ? '' : ' ' + EasTimeTools.printTime(task.dueAt)) : '') } }
        });
        LearningTaskReminders.published.set(task.id, task.remindAt);
        const latest: LearningTask | undefined = (await rdb.getLearningTasks()).find(item => item.id === task.id);
        if (latest === undefined || latest.completedAt > 0 || latest.remindAt !== task.remindAt) {
          await LearningTaskReminders.cancel(task.id);
        } else await rdb.markLearningTaskNotified(task.id, task.remindAt);
      } catch (_) { /* Retain the pending timestamp so the next loop can retry. */ }
    }
  }
}
