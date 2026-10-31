import { InsightIntentExecutor, insightIntent } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocalTimetableApi, TimetableQueryCode, TimetableQueryResponse } from '../feature/assistant/LocalTimetableApi';
import { TimetableExecutionContext } from '../feature/assistant/TimetableExecutionContext';

/** Background entry for the Timetable 0.1.0 device tool; EntryAbility supplies the real app context. */
export default class TimetableIntentExecutor extends InsightIntentExecutor {
  async onExecuteInUIAbilityBackgroundMode(name: string,
    parameters: Record<string, Object>): Promise<insightIntent.ExecuteResult> {
    const execution: TimetableExecutionContext | undefined = TimetableExecutionContext.current();
    hilog.info(0x0000, 'HitaIntent', 'execute supported=%{public}s context=%{public}s',
      String(name === LocalTimetableApi.TOOL_NAME), String(execution !== undefined));
    if (name !== LocalTimetableApi.TOOL_NAME) {
      return TimetableIntentExecutor.result(LocalTimetableApi.failure(
        TimetableQueryCode.UNSUPPORTED_TOOL, '不支持的课表工具'));
    }
    if (execution === undefined) {
      hilog.error(0x0000, 'HitaIntent', 'failed stage=context');
      return TimetableIntentExecutor.result(LocalTimetableApi.failure(
        TimetableQueryCode.READ_FAILED, 'Hita 尚未准备好，请稍后重试'));
    }
    try {
      // UIAbility.onCreate precedes background intent execution. Wait for backup recovery first.
      await execution.startup;
      if (execution !== TimetableExecutionContext.current()) throw new Error('Application context changed');
      hilog.info(0x0000, 'HitaIntent', 'startup ready; querying local timetable');
      hilog.info(0x0000, 'HitaIntent',
        'input types startDate=%{public}s endDate=%{public}s offset=%{public}s limit=%{public}s',
        typeof parameters['startDate'], typeof parameters['endDate'],
        typeof parameters['offset'], typeof parameters['limit']);
      const response: TimetableQueryResponse = await LocalTimetableApi.query(execution.context,
        TimetableIntentExecutor.queryParameters(parameters));
      hilog.info(0x0000, 'HitaIntent', 'query completed code=%{public}d returned=%{public}d total=%{public}d',
        response.code, response.result.returned, response.result.total);
      return TimetableIntentExecutor.result(response);
    } catch (_) {
      hilog.error(0x0000, 'HitaIntent', 'failed stage=startup_or_execution');
      return TimetableIntentExecutor.result(LocalTimetableApi.failure(
        TimetableQueryCode.READ_FAILED, '本地课表尚未准备好，请稍后重试'));
    }
  }

  private static queryParameters(parameters: Record<string, Object>): Record<string, Object> {
    const query: Record<string, Object> = {};
    const keys: string[] = ['startDate', 'endDate', 'relativeDate', 'teachingWeek', 'dayOfWeek', 'queryMode', 'offset', 'limit'];
    const numericKeys: string[] = ['offset', 'limit', 'teachingWeek', 'dayOfWeek'];
    for (const key of keys) {
      const value: Object | undefined = parameters[key];
      // These inputs are optional. Platform schemas can emit null/blank defaults or numeric text.
      if (value === undefined || value === null || (typeof value === 'string' && value.trim() === '')) continue;
      if (numericKeys.indexOf(key) >= 0 && typeof value === 'string' && /^\d+$/.test(value.trim())) {
        query[key] = Number(value.trim());
      } else {
        query[key] = value;
      }
    }
    // LocalTimetableApi still checks date validity, integer bounds and pagination limits.
    return query;
  }

  private static result(response: TimetableQueryResponse): insightIntent.ExecuteResult {
    // Declare result.data as String in the device plugin and enable it for model generation.
    // Keep nested course objects in JSON text so only one output leaf needs platform configuration.
    const data: string = JSON.stringify(response.result);
    hilog.info(0x0000, 'HitaIntent', 'return encoding=json chars=%{public}d', data.length);
    return {
      code: response.code,
      result: { data: data }
    };
  }
}
