import test from 'node:test';
import assert from 'node:assert/strict';
import { BackgroundTasks } from '../src/background.mjs';
import { ExpoEffects, fromSpec, toSpec } from '../src/effects.mjs';

function deferred() {
  let resolve, reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}

function storageFixture() {
  const values = new Map();
  return { values, async getItem(key) { return values.get(key) ?? null; },
    async setItem(key, value) { values.set(key, value); }, async removeItem(key) { values.delete(key); } };
}

function managerFixture() {
  const definitions = new Map(), registered = new Set(), unregistered = [];
  return { definitions, registered, unregistered,
    defineTask(name, callback) { definitions.set(name, callback); },
    async isTaskRegisteredAsync(name) { return registered.has(name); },
    async getRegisteredTasksAsync() { return [...registered].map(taskName => ({ taskName })); },
    async unregisterTaskAsync(name) { unregistered.push(name); registered.delete(name); },
    emit(name, data = null) { return definitions.get(name)({ data, error: null, executionInfo: { taskName: name, eventId: 'fixture-event' } }); } };
}

function nativeFixture(evaluate = request => ({ status: 'done', result: { value: toSpec(fromSpec(request.input).data) } })) {
  const requests = [], destroyed = [];
  let created = 0;
  return { requests, destroyed, get created() { return created; },
    async create() { return ++created; },
    async evaluate(id, raw) { const request = JSON.parse(raw); requests.push({ id, request }); return JSON.stringify(await evaluate(request, id)); },
    async resume() { throw new Error('Unexpected resume'); },
    async destroy(id) { destroyed.push(id); } };
}

function fixture(options = {}) {
  const storage = options.storage ?? storageFixture();
  const taskManager = options.taskManager ?? managerFixture();
  const native = options.native ?? nativeFixture();
  const hosts = [];
  const background = new BackgroundTasks({ storage, taskManager, native,
    hostFactory: () => { const host = new ExpoEffects({}); hosts.push(host); return host; },
    directory: '/private/documents', nativeOptions: { packages: {} }, now: () => 123,
    ...options });
  return { storage, taskManager, native, background, hosts };
}

test('fixed global tasks exist before asynchronous restoration and dispatch waits for durable source', async () => {
  const first = fixture();
  const definition = await first.background.define({ name: 'history', source: 'input.data', metadata: { version: 3 }, result_kind: 'value' });
  first.background.close();
  const gate = deferred();
  const storage = { ...first.storage, async getItem(key) { await gate.promise; return first.storage.getItem(key); } };
  const second = fixture({ storage });
  assert.equal(second.taskManager.definitions.size, 16);
  const callback = second.taskManager.emit(definition.task_name, { camelCase: 42, coordinate: 0.74 });
  assert.equal(second.native.created, 0);
  gate.resolve();
  assert.deepEqual(await callback, { camelCase: 42, coordinate: { expo_number: '0.74' } });
  const request = second.native.requests[0].request;
  assert.equal(request.source, 'input.data');
  assert.equal(request.directory, '/private/documents');
  assert.deepEqual(fromSpec(request.input), { data: { camelCase: 42, coordinate: { expo_number: '0.74' } }, error: null,
    execution_info: { taskName: definition.task_name, eventId: 'fixture-event' }, metadata: { version: 3 } });
  assert.deepEqual((await second.background.get('history')).metadata, { version: 3 });
  assert.deepEqual((await second.background.result('history')).value, { camelCase: 42, coordinate: { expo_number: '0.74' } });
  assert.deepEqual(second.native.destroyed, [1]);
  assert.equal(second.hosts[0].closed, true);
  second.background.close();
});

test('OS registration is separate and each callback owns a fresh native session', async () => {
  const { background, taskManager, native, hosts } = fixture();
  const task = await background.define({ name: 'poll', source: 'input.data' });
  assert.equal(taskManager.registered.size, 0);
  assert.equal(await taskManager.emit(task.task_name, 1), 1);
  assert.equal(await taskManager.emit(task.task_name, 2), 1);
  assert.equal(native.created, 2);
  assert.deepEqual(native.destroyed, [1, 2]);
  assert.ok(hosts.every(host => host.closed));
  assert.equal((await background.result('poll')).value, 2);
  background.close();
});

test('result kinds return Expo task/fetch enums or the EYG data value', async () => {
  for (const [result_kind, success, failure] of [['task', 1, 2], ['fetch', 2, 3], ['value', 42, null]]) {
    let fails = false;
    const native = nativeFixture(() => fails ? { status: 'error', error: 'fixture failure' } : { status: 'done', result: { value: toSpec(42) } });
    const { background, taskManager } = fixture({ native });
    const task = await background.define({ name: result_kind, source: '42', result_kind });
    assert.equal(await taskManager.emit(task.task_name), success);
    fails = true;
    assert.equal(await taskManager.emit(task.task_name), failure);
    assert.equal((await background.result(result_kind)).status, 'error');
    assert.equal(native.destroyed.length, 2);
    background.close();
  }
});

test('definition limits and malformed durable stores fail without native execution', async () => {
  const { background, native } = fixture();
  for (let i = 0; i < 16; i++) await background.define({ name: `task-${i}`, source: '42' });
  await assert.rejects(background.define({ name: 'overflow', source: '42' }), /limit/);
  for (const settings of [
    { name: '', source: '42' }, { name: 'task-0', source: '🌱'.repeat(16385) },
    { name: 'task-0', source: '' }, { name: 'task-0', source: '42', timeout_ms: 0 },
    { name: 'task-0', source: '42', timeout_ms: 300001 }, { name: 'task-0', source: '42', result_kind: 'unknown' },
    { name: 'task-0', source: '42', metadata: { number: Infinity } },
  ]) await assert.rejects(background.define(settings));
  assert.equal((await background.list()).length, 16);
  assert.equal(native.created, 0);
  background.close();
  const storage = storageFixture();
  storage.values.set('@eyg/background/v1/tasks', '{broken');
  const broken = fixture({ storage });
  await assert.rejects(broken.background.ready, SyntaxError);
  await assert.rejects(broken.background.list(), SyntaxError);
  assert.equal(await broken.taskManager.emit('eyg-background:0'), 2);
  assert.equal(broken.native.created, 0);
  broken.background.close();
});

test('timeout and cancellation abandon blocked VM calls and retain their terminal result', async () => {
  for (const timeout of [true, false]) {
    const started = deferred(), blocked = deferred();
    const native = nativeFixture(async () => { started.resolve(); return blocked.promise; });
    const { background, taskManager } = fixture({ native });
    const task = await background.define({ name: 'blocked', source: '42', timeout_ms: timeout ? 5 : 30000 });
    const callback = taskManager.emit(task.task_name);
    await started.promise;
    if (!timeout) assert.equal(await background.cancel('blocked'), true);
    assert.equal(await callback, 2);
    assert.equal((await background.result('blocked')).status, timeout ? 'timeout' : 'cancelled');
    assert.deepEqual(native.destroyed, [1]);
    blocked.reject(new Error('Late network failure'));
    await new Promise(done => setImmediate(done));
    assert.equal(background.active.size, 0);
    background.close();
  }
});

test('forget cancels active work, unregisters its OS slot, and prevents stale result restoration', async () => {
  const started = deferred(), blocked = deferred();
  const native = nativeFixture(async () => { started.resolve(); return blocked.promise; });
  const { background, taskManager, storage } = fixture({ native });
  const task = await background.define({ name: 'forget-me', source: '42' });
  taskManager.registered.add(task.task_name);
  const callback = taskManager.emit(task.task_name);
  await started.promise;
  assert.equal(await background.forget('forget-me'), true);
  assert.equal(await callback, 2);
  assert.deepEqual(taskManager.unregistered, [task.task_name]);
  assert.equal(await background.get('forget-me'), null);
  assert.equal(await background.result('forget-me'), null);
  assert.equal(await background.forget('forget-me'), false);
  blocked.resolve({ status: 'done', result: { value: toSpec(99) } });
  await new Promise(done => setImmediate(done));
  assert.equal(await background.result('forget-me'), null);
  const restarted = fixture({ storage });
  assert.deepEqual(await restarted.background.list(), []);
  background.close();
  restarted.background.close();
});

test('replacing a running definition isolates the new source and result from late old work', async () => {
  const started = deferred(), blocked = deferred();
  const native = nativeFixture(async request => {
    if (request.source === 'old') { started.resolve(); return blocked.promise; }
    return { status: 'done', result: { value: toSpec('new value') } };
  });
  const { background } = fixture({ native });
  await background.define({ name: 'replace', source: 'old' });
  const old = background.run('replace');
  await started.promise;
  await background.define({ name: 'replace', source: 'new' });
  const fresh = await background.run('replace');
  assert.equal(fresh.value, 'new value');
  assert.equal((await old).status, 'cancelled');
  blocked.resolve({ status: 'done', result: { value: toSpec('old value') } });
  await new Promise(done => setImmediate(done));
  assert.equal((await background.result('replace')).value, 'new value');
  assert.deepEqual(native.destroyed.sort(), [1, 2]);
  background.close();
});

test('OS unregistration can wait for a cancelled callback without blocking its completion', async () => {
  const started = deferred(), blocked = deferred(), unregisterStarted = deferred(), unregister = deferred();
  const native = nativeFixture(async () => { started.resolve(); return blocked.promise; });
  const { background, taskManager } = fixture({ native });
  const task = await background.define({ name: 'retiring', source: '42' });
  taskManager.registered.add(task.task_name);
  taskManager.unregisterTaskAsync = async () => { unregisterStarted.resolve(); await unregister.promise; };
  const callback = taskManager.emit(task.task_name);
  await started.promise;
  const forgetting = background.forget('retiring');
  await unregisterStarted.promise;
  assert.equal(await callback, 2);
  await assert.rejects(background.define({ name: 'retiring', source: '99' }), /being unregistered/);
  assert.equal(await taskManager.emit(task.task_name), 2);
  unregister.resolve();
  assert.equal(await forgetting, true);
  assert.equal(await background.result('retiring'), null);
  blocked.reject(new Error('Late network error'));
  await new Promise(done => setImmediate(done));
  background.close();
});

test('concurrent invocation is rejected without corrupting an active task', async () => {
  const started = deferred(), blocked = deferred();
  const native = nativeFixture(async () => { started.resolve(); return blocked.promise; });
  const { background, taskManager } = fixture({ native });
  const task = await background.define({ name: 'single', source: '42', result_kind: 'fetch' });
  const first = taskManager.emit(task.task_name);
  await started.promise;
  assert.equal(await taskManager.emit(task.task_name), 3);
  await assert.rejects(background.run('single'), /already running/);
  blocked.resolve({ status: 'done', result: { value: toSpec(42) } });
  assert.equal(await first, 2);
  assert.equal(native.created, 1);
  assert.equal((await background.result('single')).value, 42);
  background.close();
});

test('storage and unregister failures retain definitions and can be retried', async () => {
  const { background, storage, taskManager } = fixture();
  const task = await background.define({ name: 'retry', source: '42' });
  taskManager.registered.add(task.task_name);
  const unregister = taskManager.unregisterTaskAsync;
  taskManager.unregisterTaskAsync = async () => { throw new Error('OS denied unregister'); };
  await assert.rejects(background.forget('retry'), /OS denied/);
  assert.equal((await background.get('retry')).source, '42');
  taskManager.unregisterTaskAsync = unregister;
  const setItem = storage.setItem;
  storage.setItem = async () => { throw new Error('Storage full'); };
  await assert.rejects(background.define({ name: 'retry', source: '99' }), /Storage full/);
  assert.equal((await background.get('retry')).source, '42');
  await assert.rejects(background.run('retry'), /Storage full/);
  assert.equal(background.active.size, 0);
  storage.setItem = setItem;
  assert.equal(await background.forget('retry'), true);
  background.close();
});

test('adapter close cancels running tasks while preserving entrypoints for a new process', async () => {
  const started = deferred(), blocked = deferred();
  const native = nativeFixture(async () => { started.resolve(); return blocked.promise; });
  const { background, storage } = fixture({ native });
  await background.define({ name: 'durable', source: '42' });
  const execution = background.run('durable');
  await started.promise;
  background.close();
  assert.equal((await execution).status, 'cancelled');
  await assert.rejects(background.list(), /closed/);
  blocked.resolve({ status: 'done', result: { value: toSpec(42) } });
  const restarted = fixture({ storage });
  assert.equal((await restarted.background.get('durable')).source, '42');
  assert.equal((await restarted.background.run('durable', 42)).value, 42);
  restarted.background.close();
});

test('forgotten identities retain durable slot tombstones until verified reset and process restart', async () => {
  const first = fixture();
  const original = await first.background.define({ name: 'original', source: '42' });
  await first.background.forget('original');
  const other = await first.background.define({ name: 'different', source: '99' });
  assert.notEqual(other.task_name, original.task_name);
  assert.equal(await first.taskManager.emit(original.task_name, 'late old payload'), 2);
  assert.equal(first.native.created, 0);
  first.background.close();
  const restored = fixture({ storage: first.storage });
  await restored.background.forget('different');
  const same = await restored.background.define({ name: 'original', source: '100' });
  assert.equal(same.task_name, original.task_name);
  await assert.rejects(restored.background.resetSlots(), /Forget every/);
  await restored.background.forget('original');
  restored.taskManager.registered.add(original.task_name);
  await assert.rejects(restored.background.resetSlots(), /still registered/);
  restored.taskManager.registered.clear();
  assert.deepEqual(await restored.background.resetSlots(), { restart_required: true });
  await assert.rejects(restored.background.define({ name: 'after-reset', source: '1' }), /closed/);
  assert.equal(await restored.taskManager.emit(original.task_name, 'queued before reset'), 2);
  const restarted = fixture({ storage: first.storage });
  const fresh = await restarted.background.define({ name: 'after-reset', source: '1' });
  assert.equal(fresh.task_name, 'eyg-background:0');
  restarted.background.close();
});

test('slot reset gates new definitions while OS registrations are being checked', async () => {
  const { background, taskManager } = fixture();
  await background.ready;
  const started = deferred(), registrations = deferred();
  taskManager.getRegisteredTasksAsync = async () => { started.resolve(); return registrations.promise; };
  const resetting = background.resetSlots();
  await started.promise;
  await assert.rejects(background.define({ name: 'raced', source: '42' }), /reset/);
  await assert.rejects(background.resetSlots(), /reset/);
  registrations.resolve([]);
  assert.deepEqual(await resetting, { restart_required: true });
});
