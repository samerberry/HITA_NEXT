const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const test = require('node:test');
const ts = require('typescript');
const root = path.resolve(__dirname, '../entry/src/main/ets');

function harness() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'hita-backup-'));
  const context = { filesDir: directory + '/files', cacheDir: directory + '/cache', getApplicationContext() { return this; } };
  fs.mkdirSync(context.filesDir); fs.mkdirSync(context.cacheDir);
  const stores = new Map();
  let failPut = '';
  let failCommit = false;
  let committed = false;
  let captured;
  const appStorage = new Map();
  global.AppStorage = { setOrCreate: (key, value) => appStorage.set(key, value) };
  const prefs = name => {
    if (!stores.has(name)) stores.set(name, new Map());
    const values = stores.get(name);
    return {
      get: async (key, fallback) => values.has(key) ? values.get(key) : fallback,
      has: async key => values.has(key),
      put: async (key, value) => { if (key === failPut) { failPut = ''; throw Error('disk full'); } values.set(key, value); },
      delete: async key => values.delete(key), flush: async () => {}, values
    };
  };
  const io = {
    OpenMode: { READ_ONLY: fs.constants.O_RDONLY, WRITE_ONLY: fs.constants.O_WRONLY, READ_WRITE: fs.constants.O_RDWR, CREATE: fs.constants.O_CREAT, TRUNC: fs.constants.O_TRUNC },
    open: async (name, mode) => ({ fd: fs.openSync(name, mode & fs.constants.O_TRUNC ? (mode & fs.constants.O_RDWR ? 'w+' : 'w') : mode) }),
    openSync: (name, mode) => ({ fd: fs.openSync(name, mode & fs.constants.O_TRUNC ? (mode & fs.constants.O_RDWR ? 'w+' : 'w') : mode) }),
    close: async file => fs.closeSync(file.fd), closeSync: file => fs.closeSync(file.fd ?? file),
    // Force short reads/writes, exercising loops rather than assuming one call completes the stream.
    read: async (fd, array) => fs.readSync(fd, new Uint8Array(array), 0, Math.min(array.byteLength, 32749), null),
    write: async (fd, array) => fs.writeSync(fd, new Uint8Array(array), 0, Math.min(array.byteLength, 24593)),
    writeSync: (fd, text) => fs.writeSync(fd, text), statSync: file => typeof file === 'number' ? fs.fstatSync(file) : fs.statSync(file),
    fsync: async fd => fs.fsyncSync(fd), fsyncSync: fd => fs.fsyncSync(fd),
    accessSync: name => fs.existsSync(name), mkdirSync: (name, recursive) => fs.mkdirSync(name, { recursive }),
    readTextSync: name => fs.readFileSync(name, 'utf8'), renameSync: fs.renameSync,
    unlinkSync: fs.unlinkSync, listFileSync: fs.readdirSync, rmdirSync: fs.rmdirSync,
    copyFile: async (from, to) => {
      if (typeof to === 'string') fs.copyFileSync(from, to);
      else fs.writeSync(to, fs.readFileSync(from));
    }
  };
  const rdb = {
    init: async () => {}, createBackupSnapshot: async () => [],
    hasBackupReceipt: async () => committed,
    restoreBackup: async (items, receipt, apply) => {
      captured = items; await apply(); if (failCommit) throw Error('commit failed'); committed = true;
    }
  };
  const sync = { paused: false, pauseForRestore: async () => { sync.paused = true; }, resumeAfterRestore: () => { sync.paused = false; } };
  const picker = { DocumentSelectOptions: class {}, DocumentSaveOptions: class {}, DocumentViewPicker: class {
    async select() { return [directory + '/test.hita-backup']; }
    async save() { fs.writeFileSync(directory + '/export.hita-backup', ''); return [directory + '/export.hita-backup']; }
  } };
  const overrides = {
    '@kit.CoreFileKit': { fileIo: io, picker }, '@kit.ArkData': { preferences: { getPreferences: async (_, { name }) => prefs(name) } },
    '@kit.ArkTS': { buffer: { from: (...args) => Buffer.from(...args) } },
    '@kit.CryptoArchitectureKit': { cryptoFramework: { createMd: () => {
      const digest = crypto.createHash('sha256');
      return { update: async ({ data }) => digest.update(data), digest: async () => ({ data: digest.digest() }) };
    } } },
    '../../common/db/RdbHelper': { RdbHelper: { getInstance: () => rdb } },
    '../../common/theme/AppearanceStore': { AppearanceStore: { getInstance: () => ({ initialize() {}, onContentReady() {} }) } },
    '../timetable/data/ScheduleSyncService': { ScheduleSyncService: sync }
  };
  const cache = new Map();
  function load(file) {
    file = path.resolve(root, file);
    if (cache.has(file)) return cache.get(file).exports;
    const mod = { exports: {} }; cache.set(file, mod);
    const compiled = ts.transpileModule(fs.readFileSync(file, 'utf8'), {
      compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 }
    }).outputText;
    new Function('require', 'module', 'exports', compiled)(name => {
      if (overrides[name]) return overrides[name];
      if (name.startsWith('@kit.')) return {};
      return load(path.resolve(path.dirname(file), name + '.ets'));
    }, mod, mod.exports);
    return mod.exports;
  }
  return { directory, context, prefs, rdb, sync, appStorage, load, io,
    rejectPut: key => { failPut = key; }, rejectCommit: () => { failCommit = true; },
    committed: () => committed, captured: () => captured,
    close: () => fs.rmSync(directory, { recursive: true, force: true }) };
}

function fixture(h) {
  const { BackupManifest } = h.load('feature/backup/BackupModel.ets');
  const { EasTimetable, EasTermSubject, EasEventItem } = h.load('common/model/timetable/TimetableModels.ets');
  const manifest = new BackupManifest();
  const table = new EasTimetable(); table.id = 'same-id'; table.name = '学期'; table.startTime = 100; table.endTime = 200;
  const subject = new EasTermSubject(); subject.id = 'same-id'; subject.timetableId = table.id; subject.name = '数学';
  const event = new EasEventItem(); event.id = 'lesson'; event.timetableId = table.id; event.subjectId = subject.id;
  event.from = 120; event.to = 180;
  manifest.timetables = [{ timetable: table, subjects: [subject], events: [event], importBase: [{ name: '数学', from: 120, to: 180, signature: 'old-school' }] }];
  manifest.settings.activeTimetable = table.id;
  manifest.settings.classEnabled = true; manifest.settings.classMinutes = 25;
  manifest.settings.appearance = 'dark'; manifest.settings.display.wallpaperMask = 37;
  return manifest;
}

test('validated metadata preserves schedules, colors, settings and import base; identities remap independently', () => {
  const h = harness();
  try {
    const { BackupModel } = h.load('feature/backup/BackupModel.ets');
    const original = fixture(h);
    const parsed = BackupModel.parse(JSON.stringify(original));
    const first = BackupModel.remap(parsed); const second = BackupModel.remap(parsed);
    assert.equal(parsed.timetables[0].timetable.id, 'same-id');
    assert.notEqual(first.timetables[0].timetable.id, second.timetables[0].timetable.id);
    assert.equal(first.settings.activeTimetable, first.timetables[0].timetable.id);
    assert.equal(first.timetables[0].events[0].subjectId, first.timetables[0].subjects[0].id);
    assert.notEqual(first.settings.activeTimetable, first.timetables[0].subjects[0].id);
    assert.equal(first.timetables[0].subjects[0].color, original.timetables[0].subjects[0].color);
    assert.deepEqual(first.timetables[0].timetable.scheduleStructure, parsed.timetables[0].timetable.scheduleStructure);
    assert.deepEqual(first.timetables[0].importBase, parsed.timetables[0].importBase);
  } finally { h.close(); }
});

test('metadata rejects incompatible, malformed, dangling and path-bearing media records before writes', () => {
  const h = harness();
  try {
    const { BackupModel } = h.load('feature/backup/BackupModel.ets');
    for (const mutate of [
      m => { m.version = 99; }, m => { m.settings.classMinutes = '15'; },
      m => { m.timetables[0].events[0].subjectId = 'unknown'; },
      m => { m.timetables.push(m.timetables[0]); }, m => { m.timetables[0].timetable.scheduleStructure = []; },
      m => { m.settings.activeTimetable = 'missing'; }, m => { m.settings.display = null; },
      m => { m.assets = [{ role: '../outside', size: 10, sha256: 'a'.repeat(64) }]; },
      m => { m.assets = [{ role: 'video', size: 10, sha256: 'a'.repeat(64) }]; },
      m => { m.widget = { source: '../private' }; }
    ]) {
      const m = fixture(h); mutate(m); assert.throws(() => BackupModel.parse(JSON.stringify(m)));
    }
    for (const raw of ['null', '[]', '{}', '{broken']) assert.throws(() => BackupModel.parse(raw));
  } finally { h.close(); }
});

test('streaming archive round trip retains video bytes and rejects header, content, truncation and trailing corruption', async () => {
  const h = harness();
  try {
    const { BackupArchive, BackupSource } = h.load('feature/backup/BackupArchive.ets');
    const source = h.directory + '/video'; const poster = h.directory + '/poster';
    fs.writeFileSync(source, crypto.randomBytes(2 * 1024 * 1024 + 197)); fs.writeFileSync(poster, crypto.randomBytes(175));
    const archive = h.directory + '/test.hita-backup';
    await BackupArchive.create(archive, fixture(h), [new BackupSource('poster', poster), new BackupSource('video', source)], () => {});
    const result = await BackupArchive.prepare(archive, h.directory + '/prepared', () => {});
    assert.deepEqual(fs.readFileSync(result.directory + '/video'), fs.readFileSync(source));
    assert.equal(result.manifest.settings.classMinutes, 25);
    const good = fs.readFileSync(archive);
    for (const alter of [
      b => { b[0] ^= 1; return b; }, b => { b[15] ^= 1; return b; }, b => { b[60] ^= 1; return b; },
      b => { b[b.length - 1] ^= 1; return b; }, b => b.subarray(0, b.length - 1), b => Buffer.concat([b, Buffer.from('x')])
    ]) {
      fs.writeFileSync(archive, alter(Buffer.from(good)));
      await assert.rejects(BackupArchive.prepare(archive, h.directory + '/bad', () => {}));
    }
  } finally { h.close(); }
});

test('restore rolls back settings and background publication on write/commit failure and preserves account secrets', async () => {
  for (const failure of ['setting', 'commit', 'none']) {
    const h = harness();
    try {
      const { BackupService } = h.load('feature/backup/BackupService.ets');
      const prefs = h.prefs('hitanext_store').values;
      prefs.set('class_reminder_enabled', false); prefs.set('eas_password', 'private'); prefs.set('assistant_api_key', 'secret');
      h.prefs('hita_appearance').values.set('mode', 'light');
      const background = h.context.filesDir + '/timetable-background.json';
      fs.writeFileSync(background, '{"imagePath":"old.jpg","videoPath":"old.video"}');
      const prepared = { manifest: fixture(h), directory: h.context.cacheDir };
      if (failure === 'setting') h.rejectPut('exam_reminder_enabled');
      if (failure === 'commit') h.rejectCommit();
      if (failure === 'none') {
        await BackupService.restore(h.context, prepared, () => {});
        assert.equal(prefs.get('class_reminder_enabled'), true);
        assert.equal(prefs.get('class_reminder_lead_minutes'), 25);
        assert.equal(h.prefs('hita_appearance').values.get('mode'), 'dark');
        assert.equal(JSON.parse(fs.readFileSync(background)).imagePath, '');
        assert.equal(fs.readFileSync(h.context.filesDir + '/active_timetable_id.txt', 'utf8'), h.captured()[0].timetable.id);
        assert.equal(h.committed(), true);
      } else {
        await assert.rejects(BackupService.restore(h.context, prepared, () => {}));
        assert.equal(prefs.get('class_reminder_enabled'), false);
        assert.equal(prefs.has('class_reminder_lead_minutes'), false);
        assert.equal(h.prefs('hita_appearance').values.get('mode'), 'light');
        assert.equal(fs.readFileSync(background, 'utf8'), '{"imagePath":"old.jpg","videoPath":"old.video"}');
        assert.equal(h.committed(), false);
      }
      assert.equal(h.sync.paused, false);
      assert.equal(prefs.get('eas_password'), 'private'); assert.equal(prefs.get('assistant_api_key'), 'secret');
      assert.equal(fs.existsSync(h.context.filesDir + '/backup-restore-journal.json'), false);
    } finally { h.close(); }
  }
});

test('export allowlists preferences and includes selected backgrounds without credentials or device calendar registration', async () => {
  const h = harness();
  try {
    const { BackupService } = h.load('feature/backup/BackupService.ets');
    const { BackupArchive } = h.load('feature/backup/BackupArchive.ets');
    h.rdb.createBackupSnapshot = async () => fixture(h).timetables;
    const prefs = h.prefs('hitanext_store').values;
    prefs.set('eas_password', 'DO-NOT-EXPORT'); prefs.set('assistant_api_key', 'DO-NOT-EXPORT');
    prefs.set('calendar_sync', 'DO-NOT-EXPORT'); prefs.set('class_reminder_lead_minutes', 32);
    fs.writeFileSync(h.context.filesDir + '/poster.jpg', 'image-data');
    fs.writeFileSync(h.context.filesDir + '/video.video', 'video-data');
    fs.writeFileSync(h.context.filesDir + '/timetable-background.json', JSON.stringify({
      imagePath: h.context.filesDir + '/poster.jpg', videoPath: h.context.filesDir + '/video.video'
    }));
    assert.equal(await BackupService.exportFile(h.context, () => {}), true);
    const exported = h.directory + '/export.hita-backup';
    assert.equal(fs.readFileSync(exported).includes(Buffer.from('DO-NOT-EXPORT')), false);
    assert.equal(fs.readFileSync(exported).includes(Buffer.from(h.context.filesDir)), false);
    const prepared = await BackupArchive.prepare(exported, h.context.cacheDir + '/inspect', () => {});
    assert.deepEqual(prepared.manifest.assets.map(a => a.role), ['poster', 'video']);
    assert.equal(prepared.manifest.settings.classMinutes, 32);
    assert.deepEqual(fs.readdirSync(h.context.cacheDir), ['inspect']);
  } finally { h.close(); }
});

test('restore carries video and widget framing into local paths and removes staged copies after commit', async () => {
  const h = harness();
  try {
    const { BackupService } = h.load('feature/backup/BackupService.ets');
    const { TimetableBackgroundStore } = h.load('feature/timetable/data/TimetableBackgroundStore.ets');
    const { WidgetBackgroundStore } = h.load('feature/widget/WidgetBackgroundStore.ets');
    const { WidgetBackgroundState } = h.load('feature/widget/WidgetBackgroundModel.ets');
    const { BackupArchive } = h.load('feature/backup/BackupArchive.ets');
    const manifest = fixture(h);
    const widget = new WidgetBackgroundState();
    Object.assign(widget, { revision: 1, source: 'source.png', sourceWidth: 1000, sourceHeight: 700, veil: 42 });
    widget.compact = { scale: 1.7, x: 0.2, y: 0.7 }; manifest.widget = widget;
    for (const role of ['poster', 'video', 'widgetSource', 'widgetCompact', 'widgetWide']) {
      const data = Buffer.from('original-bytes-' + role);
      fs.writeFileSync(h.context.cacheDir + '/' + role, data);
      manifest.assets.push({ role, size: data.length, sha256: crypto.createHash('sha256').update(data).digest('hex') });
    }
    const prepared = { manifest, directory: h.context.cacheDir };
    await BackupService.restore(h.context, prepared, () => {});
    const background = TimetableBackgroundStore.load(h.context);
    assert.equal(fs.readFileSync(background.videoPath, 'utf8'), 'original-bytes-video');
    assert.equal(fs.readFileSync(background.imagePath, 'utf8'), 'original-bytes-poster');
    const loaded = WidgetBackgroundStore.load(h.context);
    assert.deepEqual({ ...loaded.compact }, widget.compact); assert.equal(loaded.veil, 42);
    const published = WidgetBackgroundStore.filesForPublish(h.context);
    assert.equal(fs.readFileSync(published.compactPath, 'utf8'), 'original-bytes-widgetCompact');
    assert.equal(fs.readFileSync(published.widePath, 'utf8'), 'original-bytes-widgetWide');
    assert.equal(fs.readdirSync(h.context.filesDir).some(name => name.includes('-widget')), false);
    fs.appendFileSync(h.context.cacheDir + '/video', 'tampered');
    await assert.rejects(BackupArchive.verify(prepared));
  } finally { h.close(); }
});

test('startup recovery rolls back an interrupted restore or finishes a committed restore using its durable receipt', async () => {
  for (const committed of [false, true]) {
    const h = harness();
    try {
      const { BackupService } = h.load('feature/backup/BackupService.ets');
      h.prefs('hitanext_store').values.set('class_reminder_enabled', false);
      const journal = await BackupService.capture(h.context);
      journal.receipt = 'abc-def';
      const created = h.context.filesDir + '/restored-abc-def-video.video';
      journal.created = [created]; fs.writeFileSync(created, 'video');
      fs.writeFileSync(h.context.filesDir + '/backup-restore-journal.json', JSON.stringify(journal));
      h.prefs('hitanext_store').values.set('class_reminder_enabled', true);
      fs.writeFileSync(h.context.filesDir + '/timetable-background.json', '{"imagePath":"new.jpg"}');
      if (committed) await h.rdb.restoreBackup([], journal.receipt, async () => {});
      await BackupService.recover(h.context);
      assert.equal(h.prefs('hitanext_store').values.get('class_reminder_enabled'), committed);
      assert.equal(fs.existsSync(created), committed);
      assert.equal(fs.existsSync(h.context.filesDir + '/timetable-background.json'), committed);
      assert.equal(fs.existsSync(h.context.filesDir + '/backup-restore-journal.json'), false);
      await BackupService.recover(h.context); // Recovery is safe to repeat.
    } finally { h.close(); }
  }
});

test('More places backup between portals and notices; its medium sheet keeps a shared boundary and dismissal guard', () => {
  const home = fs.readFileSync(path.join(root, 'pages/Home.ets'), 'utf8');
  const more = home.slice(home.indexOf("this.moreSectionTitle('更多')"));
  assert.ok(more.indexOf("'常用入口'") < more.indexOf("'备份与恢复'"));
  assert.ok(more.indexOf("'备份与恢复'") < more.indexOf("'公告'"));
  assert.equal((home.match(/'备份与恢复'/g) || []).length, 1);
  assert.match(home, /height: this\.backupSheetOpen \? SheetSize\.MEDIUM/);
  assert.match(home, /detents: this\.backupSheetOpen \? \[SheetSize\.MEDIUM, SheetSize\.LARGE\]/);
  assert.match(home, /if \(!this\.backupBusy\) sheetDismiss\.dismiss\(\)/);
  assert.match(home, /onDisappear:[\s\S]*this\.backupSheetOpen = false/);
  assert.match(home, /BackupPanel\(\{[\s\S]*presentedAsSheet: true/);
  const page = fs.readFileSync(path.join(root, 'feature/backup/BackupPanel.ets'), 'utf8');
  assert.match(page, /padding\(\{ top: this\.presentedAsSheet \? 0 : this\.statusBarInset \}\)/);
});
