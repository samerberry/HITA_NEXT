import { InsightIntentExecutor, insightIntent } from '@kit.AbilityKit';
import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { TimetableExecutionContext } from '../feature/assistant/TimetableExecutionContext';
import { StudyAssistantService, StudyInputError } from '../feature/assistant/StudyAssistantService';

/** Read/preparation tools cannot commit. The foreground tool only opens the local confirmation page. */
export default class StudyIntentExecutor extends InsightIntentExecutor {
  async onExecuteInUIAbilityBackgroundMode(name: string,
    parameters: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    if (['StudyQuery', 'PrepareHomework', 'PrepareTaskCompletion', 'LearningOperation'].indexOf(name) < 0) {
      return StudyIntentExecutor.result(4, { 'status': 'unsupported', 'message': '不支持此后台工具' });
    }
    try {
      const execution: TimetableExecutionContext = await StudyIntentExecutor.execution();
      let result: Record<string, Object>;
      if (name === 'StudyQuery') result = await StudyAssistantService.query(execution.context, parameters);
      else if (name === 'LearningOperation') {
        result = StudyAssistantService.operationView(await StudyAssistantService.operation(execution.context,
          StudyAssistantService.text(parameters, 'operationId')));
      } else result = await StudyAssistantService.prepare(execution.context,
        name === 'PrepareHomework' ? 'create' : 'complete', parameters);
      hilog.info(0x0000, 'HitaStudy', 'tool=%{public}s status=%{public}s', name, String(result['status']));
      return StudyIntentExecutor.result(0, result);
    } catch (error) { return StudyIntentExecutor.failure(error as Error); }
  }

  async onExecuteInUIAbilityForegroundMode(name: string, parameters: Record<string, Object>,
    _pageLoader: window.WindowStage): Promise<insightIntent.ExecuteResult> {
    if (name !== 'ConfirmLearningOperation') return StudyIntentExecutor.result(4, { 'status': 'unsupported', 'message': '不支持此前台工具' });
    try {
      const execution: TimetableExecutionContext = await StudyIntentExecutor.execution();
      const operation = await StudyAssistantService.operation(execution.context, StudyAssistantService.text(parameters, 'operationId'));
      if (operation.status === 'pending') await execution.openStudyConfirmation(operation.id);
      return StudyIntentExecutor.result(0, StudyAssistantService.operationView(operation));
    } catch (error) { return StudyIntentExecutor.failure(error as Error); }
  }

  private static async execution(): Promise<TimetableExecutionContext> {
    const execution: TimetableExecutionContext | undefined = TimetableExecutionContext.current();
    if (execution === undefined) throw new Error('Application unavailable');
    await execution.startup;
    if (execution !== TimetableExecutionContext.current()) throw new Error('Application context changed');
    return execution;
  }

  private static failure(error: Error): insightIntent.ExecuteResult {
    const invalid: boolean = error instanceof StudyInputError;
    hilog.error(0x0000, 'HitaStudy', 'tool failed validation=%{public}s', String(invalid));
    return StudyIntentExecutor.result(invalid ? 2 : 3, { 'status': 'error',
      'message': invalid ? error.message : '学习工具执行失败，请打开 HITA 后重试；本次不能视为操作成功' });
  }

  private static result(code: number, data: Record<string, Object>): insightIntent.ExecuteResult {
    return { code: code, result: { data: JSON.stringify(data) } };
  }
}
