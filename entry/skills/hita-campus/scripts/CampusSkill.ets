import { common, scriptManager } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CampusRequest, CampusSkillService } from '../../../src/main/ets/feature/assistant/CampusSkillService';

export default class CampusSkill {
  public async querySchedule(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    await this.execute(info, 'schedule', argv);
  }
  public async queryNextClass(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    await this.execute(info, 'next', argv);
  }
  public async queryExams(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    await this.execute(info, 'exams', argv);
  }
  public async prepareSchedule(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    await this.execute(info, 'add', argv);
  }
  public async prepareCourseMove(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    await this.execute(info, 'move', argv);
  }
  public async queryOperation(info: scriptManager.ArkTSScriptInfo, ...argv: string[]): Promise<void> {
    await this.execute(info, 'operation', argv);
  }

  private async execute(info: scriptManager.ArkTSScriptInfo, mode: string, argv: string[]): Promise<void> {
    let payload: Record<string, Object>;
    let code: number = 0;
    hilog.info(0x0000, 'HitaCampusSkill', 'begin %{public}s', mode);
    try {
      if (argv.length > 1) throw new Error('只允许一个 JSON 字符串参数');
      const raw = argv.length > 0 ? argv[0] : '{}';
      if (raw.length > 4096 || !raw.trim().startsWith('{')) throw new Error('参数必须是 JSON 对象字符串');
      const fields = JSON.parse(raw) as Record<string, Object>;
      const request = new CampusRequest();
      // Copy only declared strings; never accept model-supplied confirmation or arbitrary database fields.
      const keys: string[] = mode === 'next' ? [] : mode === 'operation' ? ['operationId'] :
        mode === 'add' ? ['requestKey', 'name', 'start', 'end', 'place'] :
        mode === 'move' ? ['requestKey', 'eventId', 'start', 'end', 'place'] : ['date', 'endDate', 'keyword'];
      for (const key of Object.keys(fields)) {
        if (!keys.includes(key) || typeof fields[key] !== 'string') throw new Error('未知参数或参数类型错误');
      }
      request.date = fields['date'] as string ?? 'today';
      request.endDate = fields['endDate'] as string ?? '';
      request.keyword = fields['keyword'] as string ?? '';
      request.requestKey = fields['requestKey'] as string ?? '';
      request.operationId = fields['operationId'] as string ?? '';
      request.eventId = fields['eventId'] as string ?? '';
      request.name = fields['name'] as string ?? '';
      request.start = fields['start'] as string ?? '';
      request.end = fields['end'] as string ?? '';
      request.place = fields['place'] as string ?? '';
      if (mode === 'add' || mode === 'move') {
        const operation = await CampusSkillService.prepare(info.context, mode, request);
        let opened: boolean = false;
        if (operation.status === 'pending') {
          AppStorage.setOrCreate('hita_campus_operation_waiting', operation.id);
          try {
            const context = info.context as common.UIAbilityContext;
            await context.startAbility({ bundleName: context.abilityInfo.bundleName, abilityName: 'EntryAbility',
              parameters: { hitaCampusOperation: operation.id } });
            opened = true;
          } catch (_) { /* Pending is truthful even if system foreground policy rejects the launch. */ }
        }
        payload = { 'status': operation.status, 'operationId': operation.id, 'confirmationOpened': opened,
          'message': operation.status === 'pending' ? '等待用户在 HITA 确认；尚未保存。请使用 queryOperation 查询最终结果。' : '请查询操作最终状态' };
      } else if (mode === 'operation') {
        const operation = await CampusSkillService.operation(info.context, request.operationId);
        payload = { 'status': operation.status, 'operationId': operation.id, 'event': CampusSkillService.view(operation.event) };
      } else payload = await CampusSkillService.query(info.context, mode, request);
    } catch (error) {
      code = 1;
      payload = { 'status': 'failed', 'message': (error as Error).message || '操作失败，请打开 HITA 检查后重试' };
    }
    payload['type'] = 'result';
    const result: scriptManager.ExecuteResult = { code: code, result: payload };
    try {
      await scriptManager.completeArkTSScriptInApp(info.context, info.requestCode, result);
      hilog.info(0x0000, 'HitaCampusSkill', 'complete %{public}s code=%{public}d', mode, code);
    } catch (_) { hilog.error(0x0000, 'HitaCampusSkill', 'system completion failed'); }
  }
}
