// Real native restart/hydration test; SDK and OS delivery remain fixtures.
import assert from 'node:assert/strict';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parseArgs } from 'node:util';
import { BackgroundTasks } from '../src/background.mjs';
import { ExpoEffects } from '../src/effects.mjs';
import { NativeClient } from './native-client.mjs';

const { values } = parseArgs({ options: { library: { type: 'string',
  default: fileURLToPath(new URL('../work/libeyg_android_host.so', import.meta.url)) } } });
const library = resolve(values.library);
const saved = new Map();
const storage = { async getItem(key) { return saved.get(key) ?? null; },
  async setItem(key, value) { saved.set(key, value); }, async removeItem(key) { saved.delete(key); } };
const unwrap = 'let unwrap = match { Ok(value) -> { value } Error(reason) -> { !never(perform Abort(reason)) } }';
const sourceFor = (index, factor) => `${unwrap}
let resource = unwrap(perform Expo({module: "fixture", method: "acquire"}))
let total = unwrap(perform Expo({module: "fixture", method: "sum", args: [input.data.left, input.data.right, input.metadata.offset]}))
{case: ${index}, total: !int_multiply(total, ${factor}), tag: input.metadata.tag}`;

function manager() {
  const callbacks = new Map();
  return { callbacks, defineTask(name, callback) { callbacks.set(name, callback); },
    async isTaskRegisteredAsync() { return false; }, async unregisterTaskAsync() {},
    async getRegisteredTasksAsync() { return []; },
    emit(name, data) { return callbacks.get(name)({ data, error: null, executionInfo: { taskName: name, eventId: 'cold-event' } }); } };
}

function instance(native, persistence = storage) {
  const taskManager = manager();
  const state = { acquired: 0, disposed: 0, waiting: null, hosts: [] };
  const background = new BackgroundTasks({ storage: persistence, taskManager, native,
    nativeOptions: { packages: {} }, directory: '/fixture',
    hostFactory: () => {
      const host = new ExpoEffects({ fixture: {
        acquire() { state.acquired++; return { remove() { state.disposed++; } }; },
        async sum(left, right, offset) { await Promise.resolve(); return left + right + offset; },
        wait() { return new Promise(resolve => { state.waiting = resolve; }); },
      } });
      state.hosts.push(host);
      return host;
    } });
  return { background, taskManager, state };
}

let seed = 0x455947;
const random = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
const definitions = Array.from({ length: 32 }, (_, index) => ({
  name: 'query', source: sourceFor(index, 1 + random(1000)),
  metadata: { offset: random(20001) - 10000, tag: `program-${index}` },
  result_kind: ['task', 'fetch', 'value'][index % 3],
}));
const clients = [];
const adapters = [];
const open = persistence => {
  const native = new NativeClient(library);
  clients.push(native);
  const result = { ...instance(native, persistence), native };
  adapters.push(result.background);
  return result;
};
try {
  const first = open(storage);
  const task = await first.background.define(definitions[0]);
  assert.deepEqual(await first.native.stats(), { created: 0, destroyed: 0, live: 0 });
  first.background.close();
  await first.native.close();
  clients.splice(clients.indexOf(first.native), 1);

  let hydrate;
  const gate = new Promise(resolve => { hydrate = resolve; });
  const second = open({ ...storage, async getItem(key) { await gate; return storage.getItem(key); } });
  assert.equal(second.taskManager.callbacks.size, 16);
  const cold = second.taskManager.emit(task.task_name, { left: 12, right: 30 });
  assert.deepEqual(await second.native.stats(), { created: 0, destroyed: 0, live: 0 });
  hydrate();
  assert.equal(await cold, 1);
  let completed = 1;
  const factor = Number(definitions[0].source.match(/!int_multiply\(total, (\d+)\)/)[1]);
  assert.deepEqual((await second.background.result('query')).value, {
    case: 0, total: (42 + definitions[0].metadata.offset) * factor, tag: 'program-0',
  });
  for (let index = 1; index < definitions.length; index++) {
    const definition = definitions[index];
    const task = await second.background.define(definition);
    const left = random(200001) - 100000, right = random(200001) - 100000;
    const factor = Number(definition.source.match(/!int_multiply\(total, (\d+)\)/)[1]);
    const expected = { case: index, total: (left + right + definition.metadata.offset) * factor, tag: `program-${index}` };
    const callback = await second.taskManager.emit(task.task_name, { left, right });
    assert.deepEqual(callback, definition.result_kind === 'task' ? 1 : definition.result_kind === 'fetch' ? 2 : expected);
    assert.deepEqual((await second.background.result('query')).value, expected);
    completed++;
    assert.deepEqual(await second.native.stats(), { created: completed, destroyed: completed, live: 0 });
  }
  assert.equal(second.state.acquired, 32);
  assert.equal(second.state.disposed, 32);
  assert.ok(second.state.hosts.every(host => host.closed));
  const retained = await second.background.result('query');
  second.background.close();
  await second.native.close();
  clients.splice(clients.indexOf(second.native), 1);

  const third = open(storage);
  assert.deepEqual(await third.background.result('query'), retained);
  const blocked = await third.background.define({ name: 'cancel', source: `${unwrap}
let resource = unwrap(perform Expo({module: "fixture", method: "acquire"}))
unwrap(perform Expo({module: "fixture", method: "wait"}))` });
  const execution = third.taskManager.emit(blocked.task_name, null);
  const deadline = Date.now() + 5000;
  while (!third.state.waiting) {
    assert.ok(Date.now() < deadline, 'SDK fixture was never invoked');
    await new Promise(done => setImmediate(done));
  }
  await third.background.cancel('cancel');
  assert.equal(await execution, 2);
  assert.equal((await third.background.result('cancel')).status, 'cancelled');
  third.state.waiting({ close() { third.state.disposed++; } });
  await new Promise(done => setImmediate(done));
  assert.equal(third.state.acquired, 1);
  assert.equal(third.state.disposed, 2);
  assert.ok(third.state.hosts.every(host => host.closed && host.handles.size === 0));
  assert.deepEqual(await third.native.stats(), { created: 1, destroyed: 1, live: 0 });
  console.log(JSON.stringify({ seed: '0x455947', generatedPrograms: 32, nativeProcesses: 3,
    freshNativeSessions: 33, sdkResourcesDisposed: 34, coldCallbackWaitedForHydration: 'passed',
    inputBindingsAndEffectResume: 'passed', durableResultsAcrossNativeRestart: 'passed',
    taskFetchValueFormats: 'passed', cancelledVmAndLateSdkCleanup: 'passed',
    deviceValidation: false, sdkAndOs: 'deterministic fixtures' }));
} finally {
  for (const adapter of adapters) adapter.close();
  await Promise.all(clients.map(client => client.close()));
}
