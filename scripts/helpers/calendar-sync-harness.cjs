const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const ts = require('typescript');

const root = path.resolve(__dirname, '../../entry/src/main/ets');
function harness() {
  const state = { timetables: new Map(), events: [], calendars: [], permissions: [0, 0],
    permissionCalls: 0, calendarCalls: 0, strictReads: 0, updates: 0, nextId: 1, failAt: 0, failAfterInsert: false,
    failRead: false, failDelete: false, failCreate: false, permissionGate: undefined, queryArgs: [] };
  const makeCalendar = account => ({
    id: state.calendars.length + 1, rows: [], config: { enableReminder: true }, getAccount: () => account,
    async getConfig() { return { ...this.config }; },
    async setConfig(config) { this.config = { ...config }; },
    async getEvents(...args) {
      state.queryArgs.push(args);
      // Match native overload dispatch: an omitted filter works, explicit undefined does not.
      if (args.length > 0 && (args[0] === undefined || args[0] === null)) {
        throw Object.assign(new Error('Parameter error: invalid event filter'), { code: 401 });
      }
      if (state.failRead) throw new Error('Read failed');
      return this.rows.map(row => ({ ...row }));
    },
    async addEvent(event) {
      if (state.failAt === state.nextId && !state.failAfterInsert) return -1;
      const id = state.nextId++;
      this.rows.push({ ...event, id });
      if (state.failAfterInsert) {
        state.failAfterInsert = false;
        throw new Error('Committed but response lost');
      }
      return id;
    },
    async updateEvent(event) {
      state.updates++;
      const index = this.rows.findIndex(row => row.id === event.id);
      assert.ok(index >= 0);
      this.rows[index] = { ...event };
    },
    async deleteEvent(id) {
      if (state.failDelete) throw new Error('Delete failed');
      this.rows = this.rows.filter(row => row.id !== id);
    }
  });
  const api = {
    CalendarType: { LOCAL: 'local' }, EventType: { NORMAL: 0 },
    getCalendarManager() {
      state.calendarCalls++;
      return {
        async getAllCalendars() { return state.calendars; },
        async createCalendar(account) {
          if (state.failCreate) return { id: -1 };
          const calendar = makeCalendar(account);
          state.calendars.push(calendar);
          return calendar;
        }
      };
    }
  };
  const rdb = {
    async init() {},
    async getTimetableById(id, strict) {
      if (state.failDb) throw new Error('Database unavailable');
      if (strict) state.strictReads++;
      return state.timetables.get(id);
    },
    async getTimetables() { return [...state.timetables.values()]; },
    async getEventsOfTimetable(id, strict) {
      if (state.failDbEvents) throw new Error('Database rows unavailable');
      if (strict) state.strictReads++;
      return state.events.filter(event => event.timetableId === id);
    }
  };
  const prefs = new Map();
  const published = [];
  const statuses = new Map();
  global.AppStorage = { setOrCreate: (key, value) => statuses.set(key, value) };
  const cache = new Map();
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} };
    cache.set(file, mod);
    const platform = name => {
      if (name.endsWith('/db/RdbHelper')) return { RdbHelper: { getInstance: () => rdb } };
      if (name === '@kit.ArkData') return { preferences: { getPreferences: async (ctx, options) => {
        if (!prefs.has(options.name)) prefs.set(options.name, new Map());
        const values = prefs.get(options.name);
        return { get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
          put: async (key, value) => values.set(key, value), flush: async () => {} };
      } } };
      if (name === '@kit.NotificationKit') return { notificationManager: {
        SlotType: { SOCIAL_COMMUNICATION: 1 }, ContentType: { NOTIFICATION_CONTENT_BASIC_TEXT: 0 },
        addSlot: async () => {}, publish: async request => published.push(request)
      } };
      if (name === '@kit.CalendarKit') return { calendarManager: api };
      if (name === '@kit.AbilityKit') return { abilityAccessCtrl: { createAtManager: () => ({
        async requestPermissionsFromUser(ctx, permissions) {
          state.permissionCalls++;
          assert.deepEqual(permissions, ['ohos.permission.READ_CALENDAR', 'ohos.permission.WRITE_CALENDAR']);
          if (state.permissionGate) await state.permissionGate;
          return { authResults: state.permissions };
        }
      }) } };
      if (name === '@kit.PerformanceAnalysisKit') return { hilog: { info() {}, warn() {}, error() {} } };
      if (name.startsWith('@kit.')) return {};
      return load(path.resolve(path.dirname(file), name + '.ets'));
    };
    const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', compiled)(platform, mod, mod.exports);
    return mod.exports;
  }
  const { EasTimetable, EasEventItem } = load('common/model/timetable/TimetableModels.ets');
  const { TimetableCalendarExporter: exporter } = load('feature/timetable/data/TimetableCalendarExporter.ets');
  const timetable = Object.assign(new EasTimetable(), { id: 'term-a', name: '2026 秋季' });
  state.timetables.set(timetable.id, timetable);
  const course = (overrides = {}) => Object.assign(new EasEventItem(), {
    timetableId: timetable.id, name: '高等数学', teacher: '张老师', place: 'A101',
    from: Date.parse('2026-10-05T08:30:00+08:00'), to: Date.parse('2026-10-05T10:15:00+08:00'),
    fromNumber: 1, lastNumber: 2
  }, overrides);
  const run = (selected = timetable) => exporter.exportTimetable({}, selected);
  return { state, course, timetable, run, exporter, makeCalendar, load, prefs, published, statuses };
}

module.exports = { harness };

