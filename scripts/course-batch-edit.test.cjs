const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');
global.$r = x => x;
global.DialogAlignment = { Bottom: 'bottom' };

function load(relative, overrides = {}, cache = new Map()) {
  const file = path.resolve(root, relative);
  if (cache.has(file)) return cache.get(file).exports;
  let source = fs.readFileSync(file, 'utf8');
  if (file.endsWith('AddEventPage.ets')) {
    source = source.slice(0, source.indexOf('\n  build()')) + '\n}\n';
    source = source.replace(/^@Component\r?\n/gm, '')
      .replace(/@(State|Prop|StorageProp)(\([^)]*\))?\s+/g, '')
      .replace('export struct EventEditorForm', 'export class EventEditorForm');
  }
  const mod = { exports: {} };
  cache.set(file, mod);
  const compiled = ts.transpileModule(source, { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020
  } }).outputText;
  new Function('require', 'module', 'exports', compiled)(name => {
    if (name.endsWith('/RdbHelper') && overrides.db) return { RdbHelper: { getInstance: () => overrides.db } };
    if (name.endsWith('/CourseTimePickerDialog')) return { CourseTimePickerDialog: options => options };
    if (name.endsWith('/CourseTextPickerDialog')) return { CourseTextPickerDialog: options => options };
    if (name.endsWith('/CompatibleSheetMaterial')) return { CompatibleSheetMaterial: {
      isEnabled: () => false, cardColor: fallback => fallback
    } };
    if (name.endsWith('/CompatiblePickerMaterial')) return { CompatiblePickerMaterial: {
      isEnabled: () => overrides.pickerEnabled === true, textOptions: options => options,
      dialogMaterial: () => overrides.pickerEnabled ? 'controlled-material' : undefined
    } };
    if (name === '@kit.PerformanceAnalysisKit') return { hilog: { error() {} } };
    if (name === '@kit.ArkData') return { relationalStore: { RdbPredicates: class {
      constructor(table) { this.table = table; this.filters = []; }
      equalTo(key, value) { this.filters.push([key, value]); return this; }
    } } };
    if (name.startsWith('@kit.')) return {};
    return load(path.resolve(path.dirname(file), name + '.ets'), overrides, cache);
  }, mod, mod.exports);
  return mod.exports;
}

const { EasTimetable, EasEventItem, EasEventType } = load('common/model/timetable/TimetableModels.ets');
const { CourseBatchEdit: Batch } = load('feature/timetable/CourseBatchEdit.ets');
const { RdbHelper } = load('common/db/RdbHelper.ets');
const tt = Object.assign(new EasTimetable(), { id: 't', startTime: new Date(2026, 7, 31).getTime(), endTime: new Date(2027, 0, 18).getTime() - 1 });
function event(id, week, extra = {}) {
  return Object.assign(new EasEventItem(), { id, timetableId: 't', subjectId: 's', type: EasEventType.CLASS,
    name: '数学', place: 'A101', teacher: '张老师', from: tt.startTime + (week - 1) * 7 * 86400000 + 8 * 3600000,
    to: tt.startTime + (week - 1) * 7 * 86400000 + 9 * 3600000, fromNumber: 1, lastNumber: 2, color: 0 }, extra);
}
const series = () => [event('a',1), event('b',2), event('c',3), event('exam',2,{type:EasEventType.EXAM}),
  event('other-subject',2,{subjectId:'another'}), event('other-table',2,{timetableId:'another'})];
test('scopes select only explicit course identity, selected weeks or future classes', () => {
  const items=series(), anchor=items[1];
  assert.deepEqual(Batch.targets(items,anchor,0,[],tt).map(e=>e.id),['b']);
  assert.deepEqual(Batch.targets(items,anchor,1,[1,3],tt).map(e=>e.id),['a','c']);
  assert.deepEqual(Batch.targets(items,anchor,2,[],tt).map(e=>e.id),['b','c']);
  assert.equal(Batch.targets(items,anchor,1,[],tt).length,0);
  const orphan=event('orphan',1,{subjectId:''});
  assert.deepEqual(Batch.targets([...items,orphan],orphan,2,[],tt).map(e=>e.id),['orphan']);
});
test('room-only updates preserve per-occurrence times, teacher and period numbers', () => {
  const anchor=event('a',1), second=event('b',2,{teacher:'李老师'});
  second.from+=2*3600000; second.to+=2*3600000;
  const edited=Batch.copy(anchor); edited.place='B202';
  const result=Batch.update([anchor,second],anchor,edited);
  assert.deepEqual(result.map(e=>e.place),['B202','B202']);
  assert.equal(result[1].teacher,'李老师'); assert.equal(result[1].from,second.from);
  assert.equal(result[1].fromNumber,1); assert.equal(anchor.place,'A101');
});
test('clock edits clear period metadata and date shifts preserve spacing and IDs', () => {
  const anchor=event('a',1), next=event('b',2), edited=Batch.copy(anchor);
  edited.from+=86400000+30*60000; edited.to+=86400000+30*60000;
  const result=Batch.update([anchor,next],anchor,edited);
  assert.deepEqual(result.map(e=>e.id),['a','b']);
  assert.equal(result[1].from-result[0].from,7*86400000);
  assert.equal(result[1].fromNumber,0); assert.equal(result[1].lastNumber,0);
  const dateOnly=Batch.copy(anchor); dateOnly.from+=86400000; dateOnly.to+=86400000;
  assert.equal(Batch.update([anchor],anchor,dateOnly)[0].fromNumber,1);
});
function database(items=series(), failAt=-1) {
  const rows={ timetable:[{id:'t',endTime:tt.endTime}], subject:[{id:'s',timetableId:'t'}],
    events:items.map(item=>RdbHelper.eventValues(item)) };
  const db=new RdbHelper(); let writes=0;
  db.store={createTransaction:async()=>{
    const pending=structuredClone(rows);
    const matching=(pred)=>pending[pred.table].filter(row=>pred.filters.every(([k,v])=>row[k]===v));
    return {
      query:async pred=>{const row=matching(pred)[0];return {goToFirstRow:()=>!!row,goToNextRow:()=>!!row,
        getColumnIndex:k=>k,getLong:k=>Number(row[k]||0),getString:k=>String(row[k]||''),close(){}};},
      update:async(value,pred)=>{if(writes++===failAt)throw Error('disk full');const found=matching(pred);found.forEach(r=>Object.assign(r,value));return found.length;},
      delete:async pred=>{if(writes++===failAt)throw Error('disk full');const found=matching(pred);pending[pred.table]=pending[pred.table].filter(r=>!found.includes(r));return found.length;},
      insert:async(table,value)=>{if(writes++===failAt)throw Error('disk full');pending[table].push({...value});return pending[table].length;},
      commit:async()=>Object.assign(rows,pending),rollback:async()=>{}
    };
  }};return {db,rows};
}
test('bulk edits and undo commit atomically without touching exams or other courses',async()=>{
  const items=series(), before=items.slice(0,3), edited=Batch.copy(before[0]);edited.place='新教室';
  const after=Batch.update(before,before[0],edited), {db,rows}=database(items);
  const initial=structuredClone(rows);
  await db.replaceCourseOccurrences(before,after,'t');
  assert.deepEqual(rows.events.slice(0,3).map(e=>e.place),['新教室','新教室','新教室']);
  assert.deepEqual(rows.events.slice(3),initial.events.slice(3));
  await db.replaceCourseOccurrences(after,before,'t');assert.deepEqual(rows,initial);
});
test('stop selected occurrences and undo preserve original IDs and metadata',async()=>{
  const items=series(), before=items.slice(1,3), {db,rows}=database(items);
  await db.replaceCourseOccurrences(before,[],'t');assert.deepEqual(rows.events.map(e=>e.id),['a','exam','other-subject','other-table']);
  await db.replaceCourseOccurrences([],before,'t');
  assert.deepEqual(rows.events.filter(e=>['b','c'].includes(e.id)),before.map(e=>RdbHelper.eventValues(e)));
});
test('failed second edit or deletion rolls back the complete operation',async()=>{
  for(const stop of [false,true]) {
    const items=series(),before=items.slice(0,3),edited=Batch.copy(before[0]);edited.place='new';
    const {db,rows}=database(items,1),initial=structuredClone(rows);
    await assert.rejects(db.replaceCourseOccurrences(before,stop?[]:Batch.update(before,before[0],edited),'t'),/disk full/);
    assert.deepEqual(rows,initial);
  }
});
test('concurrent changes and deleted timetables reject before writing, undo never overwrites a newer edit',async()=>{
  const items=series(),before=items.slice(0,2),edited=Batch.copy(before[0]);edited.place='new';
  const after=Batch.update(before,before[0],edited),{db,rows}=database(items);
  await db.replaceCourseOccurrences(before,after,'t'); rows.events[0].teacher='updated elsewhere';
  const current=structuredClone(rows);
  await assert.rejects(db.replaceCourseOccurrences(after,before,'t'),/Course changed/);assert.deepEqual(rows,current);
  rows.timetable=[];
  await assert.rejects(db.replaceCourseOccurrences(after,before,'t'),/Timetable no longer exists/);
});
test('undo cannot resurrect a deleted subject or overwrite a reused occurrence ID',async()=>{
  const before=[event('a',1)],{db,rows}=database(before);
  await db.replaceCourseOccurrences(before,[],'t'); rows.subject=[];
  await assert.rejects(db.replaceCourseOccurrences([],before,'t'),/Subject no longer exists/);
  assert.equal(rows.events.length,0);
  rows.subject=[{id:'s',timetableId:'t'}];rows.events=[RdbHelper.eventValues(event('a',2))];
  await assert.rejects(db.replaceCourseOccurrences([],before,'t'),/already exists/);
  assert.equal(rows.events[0].fromTime,event('a',2).from);
});
test('both entry points share the detail component and the color strip has no action',()=>{
  const home=fs.readFileSync(path.join(root,'pages/Home.ets'),'utf8');
  const detail=fs.readFileSync(path.join(root,'pages/TimetableDetailPage.ets'),'utf8');
  assert.match(home,/CourseDetailContent\(\{/);assert.match(detail,/CourseDetailContent\(\{/);
  assert.match(detail,/deleteLabel: '删除'/);assert.doesNotMatch(detail,/cycleColor|SUBJECT_PALETTE/);
});

function editor(choices = [1,0], writeFailure = false) {
  const original=event('a',1), writes=[],changes=[];
  const db={replaceCourseOccurrences:async(before,after)=>{
    if(writeFailure)throw Error('disk full');
    writes.push({before,after});
  }};
  const {EventEditorForm}=load('pages/AddEventPage.ets',{db});const form=new EventEditorForm();
  let saved;
  const toasts=[];
  const day=new Date(original.from);day.setHours(0,0,0,0);
  Object.assign(form,{originalCourse:original,relatedCourses:[original,event('b',2)],typeIdx:1,
    editId:original.id,editScope:2,courseTimetable:tt,todayBase:day.getTime(),dayOffset:0,
    name:original.name,place:'new room',teacher:original.teacher,hour:8,minute:0,endHour:9,endMinute:0,
    loading:false,editorActive:true,sheetMode:true,onSaved:(_ev,items)=>{saved=items;},
    onChanged:async()=>changes.push('changed')});
  form.getUIContext=()=>({getPromptAction:()=>({showDialog:async()=>{
    const next=choices.shift();if(next instanceof Error)throw next;return {index:next};
  },showToast:message=>toasts.push(message)})});
  return {form,writes,changes,toasts,get saved(){return saved;}};
}
test('editor confirms the affected scope and applies or undoes both reschedule and stop',async()=>{
  for(const stopping of [false,true])for(const undo of [false,true]) {
    const harness=editor([1,undo?1:0]);harness.form.stoppingCourse=stopping;
    await harness.form.save();
    assert.equal(harness.writes.length,undo?2:1);
    assert.equal(harness.writes[0].before.length,2);
    assert.equal(harness.writes[0].after.length,stopping?0:2);
    assert.equal(harness.saved.length,stopping&&!undo?0:2);
    assert.equal(harness.changes.length,undo?2:1);
  }
});
test('cancel, native dialog dismissal and write failure leave the editor retryable',async()=>{
  for(const choice of [0,Error('cancel')]) {
    const h=editor([choice]);await h.form.save();
    assert.equal(h.writes.length,0);assert.equal(h.form.saved,false);assert.equal(h.form.saving,false);
    assert.equal(h.form.hint,'');
  }
  const failed=editor([1],true);await failed.form.save();
  assert.equal(failed.saved,undefined);assert.equal(failed.form.saving,false);assert.match(failed.form.hint,/保存失败/);
});
test('no matching weeks disable saving and a late confirmation after closing cannot write',async()=>{
  const h=editor([1,0]);h.form.editScope=1;h.form.selectedWeeks=[];
  assert.equal(h.form.canSave(),false);await h.form.save();assert.equal(h.writes.length,0);
  const late=editor([1]);late.form.getUIContext=()=>({getPromptAction:()=>({showDialog:async()=>{
    late.form.editorActive=false;return {index:1};
  }})});await late.form.save();assert.equal(late.writes.length,0);
});

test('the timetable closes its detail sheet before opening the editor and preserves the viewed week',async()=>{
  const source=fs.readFileSync(path.join(root,'pages/Home.ets'),'utf8');
  const method=source.slice(source.indexOf('  private async editCourse('),source.indexOf('  private static canvasColorCss'));
  const js=ts.transpileModule('class Host {'+method+'};module.exports=Host',{
    compilerOptions:{target:ts.ScriptTarget.ES2020}}).outputText;
  const mod={exports:{}};new Function('module',js)(mod);
  const host=new mod.exports();host.pageVisible=true;host.skippingCourse=false;
  let close;const routes=[];
  host.closeCourseSheetBeforeSkip=()=>new Promise(resolve=>{close=resolve;});
  host.getUIContext=()=>({getRouter:()=>({pushUrl:async options=>routes.push(options)})});
  const job=host.editCourse(event('a',1));
  assert.equal(routes.length,0);close();await job;
  assert.equal(routes[0].params.id,'a');assert.equal(host.returningFromCourseEditor,true);
  host.pageVisible=true;const late=host.editCourse(event('b',2));host.pageVisible=false;close();await late;
  assert.equal(routes.length,1);
});
