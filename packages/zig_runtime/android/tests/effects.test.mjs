import test from 'node:test';
import assert from 'node:assert/strict';
import { ExpoEffects, fromSpec, toSpec } from '../src/effects.mjs';
import { runSession } from '../src/session.mjs';

function deferred() {
  let resolve, reject;
  const promise = new Promise((done, fail) => { resolve = done; reject = fail; });
  return { promise, resolve, reject };
}

async function promptly(promise) {
  let timer;
  try {
    return await Promise.race([promise, new Promise((_, reject) => {
      timer = setTimeout(() => reject(new Error('Cancellation waited for blocked IO')), 1000);
    })]);
  } finally {
    clearTimeout(timer);
  }
}

test('wide finite EYG integers remain numbers and non-finite wire placeholders are rejected', () => {
  assert.equal(fromSpec({ integer: 1e100 }), 1e100);
  for (const integer of [null, undefined, '42', 0.5, Infinity, -Infinity, NaN]) {
    assert.throws(() => fromSpec({ integer }), /finite integer/);
  }
});

test('EYG source spellings select handles, wait for events, and express foreign field names', async () => {
  const host = new ExpoEffects({ api: { echo(value) { return value; }, async pending() { return 42; } } });
  const deferred = await host.perform('Expo', { module: 'api', method: 'pending', defer: true });
  assert.equal(await host.perform('Expo', { expo_handle: deferred.expo_handle, method: '$await' }), 42);
  assert.equal(await host.perform('ExpoNextEvent', { timeout_ms: 0 }), null);
  const options = { expo_object: [{ key: 'shouldShowBanner', value: true }, { key: 'a.b', value: { expo_date: '2026-10-28T00:00:00.000Z' } }] };
  const echoed = await host.perform('Expo', { module: 'api', method: 'echo', args: [options] });
  assert.deepEqual(echoed, { shouldShowBanner: true, 'a.b': { expo_date: '2026-10-28T00:00:00.000Z' } });
  assert.equal(await host.perform('Expo', { object: echoed, method: 'shouldShowBanner', get: true }), true);
  assert.deepEqual(await host.perform('Expo', { object: echoed, method: ['a.b'], get: true }), { expo_date: '2026-10-28T00:00:00.000Z' });
  await host.close();
});

test('generated data values round trip through the EYG effect boundary', () => {
  let seed = 0x455947;
  const rng = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
  function value(depth) {
    const kind = rng(depth ? 7 : 4);
    if (kind === 0) return rng(100000) - 50000;
    if (kind === 1) return ['é', '绿', '\u0000', '\n', '🚀'][rng(5)];
    if (kind === 2) return rng(2) === 1;
    if (kind === 3) return null;
    if (kind === 4) return Array.from({ length: rng(6) }, () => value(depth - 1));
    return Object.fromEntries(Array.from({ length: rng(6) }, (_, i) => [`key${i}`, value(depth - 1)]));
  }
  for (let i = 0; i < 2000; i++) { const input = value(4); assert.deepEqual(fromSpec(toSpec(input)), input); }
});

test('async functions preserve this and permission denial is returned as data', async () => {
  const sdk = { granted: false, async requestPermissionsAsync() { return { granted: this.granted }; } };
  const host = new ExpoEffects({ permissions: sdk });
  assert.deepEqual(await host.perform('Expo', { module: 'permissions', method: 'requestPermissionsAsync' }), { granted: false });
  await assert.rejects(host.perform('Expo', { module: 'permissions', method: '__proto__.toString' }), /Invalid/);
  await host.close();
});

test('fractional Expo numbers and binary data retain their types across EYG', async () => {
  const host = new ExpoEffects({ location: { get() { return { latitude: 51.5072, battery: 0.74 }; }, echo(value) { return value; } } });
  const encoded = await host.perform('Expo', { module: 'location', method: 'get' });
  assert.deepEqual(encoded, { latitude: { expo_number: '51.5072' }, battery: { expo_number: '0.74' } });
  const eyg = fromSpec(toSpec(encoded));
  assert.deepEqual(host.decode(eyg), { latitude: 51.5072, battery: 0.74 });
  assert.deepEqual(host.decode(fromSpec({ binary: { '/': { bytes: 'AQD/' } } })), Uint8Array.from([1, 0, 255]));
  await host.close();
});

test('subscriptions yield events, objects retain identity, and close removes resources', async () => {
  let callback, removed = 0;
  const subscription = { remove() { removed++; } };
  const host = new ExpoEffects({ sensor: { addListener(cb) { callback = cb; return subscription; } } });
  const handle = await host.perform('Expo', { module: 'sensor', method: 'addListener', args: [{ expo_callback: 'motion' }] });
  assert.ok(handle.expo_handle);
  const next = host.perform('ExpoNextEvent', { timeoutMs: 1000 });
  callback({ x: 12, y: 42 });
  assert.deepEqual(await next, { topic: 'motion', args: [{ x: 12, y: 42 }], dropped: 0 });
  await host.close();
  assert.equal(removed, 1);
  await assert.rejects(host.perform('Expo', { module: 'sensor', method: 'addListener' }), /closed/);
});

test('bounded event queue and cancellation finish pending waits', async () => {
  const host = new ExpoEffects({}, null, 2);
  for (let i = 0; i < 5; i++) host.emit('event', [i]);
  const first = await host.nextEvent(0);
  assert.deepEqual(first.args, [3]);
  assert.equal(first.dropped, 3);
  assert.deepEqual((await host.nextEvent(0)).args, [4]);
  const pending = host.nextEvent(1000);
  await host.close();
  assert.equal(await pending, null);
  assert.equal(host.dropped, 3);
});

test('native object handle method binding and release', async () => {
  class Database { count = 0; query(n) { this.count += n; return this.count; } close() { this.count = -1; } }
  const database = new Database();
  const host = new ExpoEffects({ sqlite: { open() { return database; } } });
  const handle = await host.perform('Expo', { module: 'sqlite', method: 'open' });
  assert.equal(await host.perform('Expo', { handle: handle.expo_handle, method: 'query', args: [21] }), 21);
  await host.perform('ExpoRelease', { handle: handle.expo_handle });
  assert.equal(database.count, -1);
  await assert.rejects(host.perform('Expo', { handle: handle.expo_handle, method: 'query' }), /Unknown/);
});

test('cancellation disposes objects returned after a pending API finishes', async () => {
  let resolve, removed = 0;
  const pending = new Promise(done => { resolve = done; });
  const host = new ExpoEffects({ api: { async open() { return pending; } } });
  const call = host.perform('Expo', { module: 'api', method: 'open' });
  await host.close();
  resolve({ remove() { removed++; } });
  await assert.rejects(call, /closed/);
  assert.equal(removed, 1);
  assert.equal(host.handles.size, 0);
});

test('view effects delegate component ownership and close with the session', async () => {
  let current, clear = 0;
  const host = new ExpoEffects({}, { show: spec => { current = spec; return spec.id; }, close: id => { current = null; return id; }, clear: () => clear++ });
  assert.equal(await host.perform('ExpoView', { id: 'camera', module: 'expo-camera', component: 'CameraView' }), 'camera');
  assert.equal(current.component, 'CameraView');
  assert.equal(await host.perform('ExpoView', { action: 'close', id: 'camera' }), 'camera');
  await host.close();
  assert.equal(clear, 1);
});

test('session continues across async effects and always destroys native storage', async () => {
  let destroyed = false, resumed;
  const native = {
    async create() { return 7; },
    async evaluate(id, input) { assert.equal(id, 7); assert.equal(JSON.parse(input).source, 'program'); return JSON.stringify({ status: 'effect', effect: { label: 'Expo', value: toSpec({ module: 'battery', method: 'getLevel' }) } }); },
    async resume(id, reply) { resumed = JSON.parse(reply); return JSON.stringify({ status: 'done', result: { value: { integer: 42 } } }); },
    async destroy(id) { assert.equal(id, 7); destroyed = true; },
  };
  const result = await runSession(native, new ExpoEffects({ battery: { async getLevel() { return 42; } } }), 'program');
  assert.equal(result.status, 'done');
  assert.deepEqual(resumed, { tagged: { label: 'Ok', value: { integer: 42 } } });
  assert.equal(destroyed, true);
});

test('abort abandons blocked native evaluation and ignores its late effect response', async () => {
  const started = deferred(), evaluation = deferred(), cleanup = deferred();
  const controller = new AbortController();
  const destroyed = [], updates = [];
  let resumes = 0;
  const host = new ExpoEffects({});
  host.encode({ remove() { return cleanup.promise; } });
  const native = {
    async create() { return 7; },
    evaluate(id, input) {
      assert.equal(id, 7);
      assert.deepEqual(JSON.parse(input), { source: 'blocked', directory: '/fixture' });
      started.resolve();
      return evaluation.promise;
    },
    async resume() { resumes++; throw new Error('Late response must be ignored'); },
    async destroy(id) { destroyed.push(id); },
  };
  const session = runSession(native, host, 'blocked', state => updates.push(state), undefined, { directory: '/fixture' }, controller.signal);
  await started.promise;
  controller.abort();
  assert.deepEqual(await promptly(session), { status: 'cancelled' });
  assert.equal(host.closed, true);
  assert.deepEqual(destroyed, [7]);
  evaluation.resolve(JSON.stringify({ status: 'effect', effect: { label: 'Expo', value: toSpec({}) } }));
  cleanup.resolve();
  await new Promise(done => setImmediate(done));
  assert.deepEqual(updates, []);
  assert.equal(resumes, 0);
  assert.deepEqual(destroyed, [7]);
});

test('abort abandons blocked native resume and observes a late rejection', async () => {
  const started = deferred(), resumption = deferred();
  const controller = new AbortController();
  const destroyed = [];
  const native = {
    async create() { return 8; },
    async evaluate() { return JSON.stringify({ status: 'effect', effect: { label: 'Expo', value: toSpec({ module: 'sdk', method: 'answer' }) } }); },
    resume() { started.resolve(); return resumption.promise; },
    async destroy(id) { destroyed.push(id); },
  };
  const host = new ExpoEffects({ sdk: { answer() { return 42; } } });
  const session = runSession(native, host, 'resume', undefined, undefined, {}, controller.signal);
  await started.promise;
  controller.abort();
  assert.deepEqual(await promptly(session), { status: 'cancelled' });
  assert.deepEqual(destroyed, [8]);
  resumption.reject(new Error('Native network failed after cancellation'));
  await new Promise(done => setImmediate(done));
  assert.equal(host.closed, true);
  assert.deepEqual(destroyed, [8]);
});

test('abort during native creation destroys a late session once and observes late allocation errors', async () => {
  for (const succeeds of [true, false]) {
    const started = deferred(), creation = deferred();
    const controller = new AbortController();
    const destroyed = [];
    let evaluations = 0;
    const native = {
      create() { started.resolve(); return creation.promise; },
      async evaluate() { evaluations++; throw new Error('Cancelled creation cannot evaluate'); },
      async destroy(id) { destroyed.push(id); },
    };
    const host = new ExpoEffects({});
    const session = runSession(native, host, 'create', undefined, undefined, {}, controller.signal);
    await started.promise;
    controller.abort();
    assert.deepEqual(await promptly(session), { status: 'cancelled' });
    assert.equal(host.closed, true);
    assert.deepEqual(destroyed, []);
    if (succeeds) creation.resolve(9);
    else creation.reject(new Error('Late allocation failure'));
    await new Promise(done => setImmediate(done));
    assert.deepEqual(destroyed, succeeds ? [9] : []);
    assert.equal(evaluations, 0);
  }
});

test('an already aborted run closes its host without creating native storage', async () => {
  const controller = new AbortController();
  controller.abort();
  const host = new ExpoEffects({});
  const native = { async create() { throw new Error('Must not allocate'); } };
  assert.deepEqual(await runSession(native, host, 'unused', undefined, undefined, {}, controller.signal), { status: 'cancelled' });
  assert.equal(host.closed, true);
});

test('abort during an SDK call returns promptly and disposes its late native resource', async () => {
  const started = deferred(), operation = deferred();
  const controller = new AbortController();
  let destroyed = 0, disposed = 0, resumed = 0;
  const host = new ExpoEffects({ sdk: { open() { started.resolve(); return operation.promise; } } });
  const native = {
    async create() { return 10; },
    async evaluate() { return JSON.stringify({ status: 'effect', effect: { label: 'Expo', value: toSpec({ module: 'sdk', method: 'open' }) } }); },
    async resume() { resumed++; },
    async destroy() { destroyed++; },
  };
  const session = runSession(native, host, 'sdk', undefined, undefined, {}, controller.signal);
  await started.promise;
  controller.abort();
  assert.deepEqual(await promptly(session), { status: 'cancelled' });
  assert.equal(destroyed, 1);
  operation.resolve({ close() { disposed++; } });
  await new Promise(done => setImmediate(done));
  assert.equal(disposed, 1);
  assert.equal(resumed, 0);
  assert.equal(host.handles.size, 0);
});

test('abort can abandon slow cleanup after the native result has already completed', async () => {
  const started = deferred(), cleanup = deferred();
  const controller = new AbortController();
  let destroyed = 0;
  const host = new ExpoEffects({});
  host.encode({ remove() { started.resolve(); return cleanup.promise; } });
  const native = {
    async create() { return 11; },
    async evaluate() { return JSON.stringify({ status: 'done', result: { value: toSpec(42) } }); },
    async destroy() { destroyed++; },
  };
  const session = runSession(native, host, 'cleanup', undefined, undefined, {}, controller.signal);
  await started.promise;
  controller.abort();
  assert.deepEqual(await promptly(session), { status: 'cancelled' });
  assert.equal(destroyed, 1);
  cleanup.resolve();
  await new Promise(done => setImmediate(done));
});

test('a new session stays independent while an abandoned native call fails later', async () => {
  const oldStarted = deferred(), oldCall = deferred(), newStarted = deferred(), sdkCall = deferred();
  const oldController = new AbortController();
  const oldUpdates = [], newUpdates = [], destroyed = [];
  let nextId = 0;
  const native = {
    async create() { return ++nextId; },
    async evaluate(id) {
      if (id === 1) { oldStarted.resolve(); return oldCall.promise; }
      return JSON.stringify({ status: 'effect', effect: { label: 'Expo', value: toSpec({ module: 'sdk', method: 'run' }) } });
    },
    async resume(id, reply) {
      assert.equal(id, 2);
      assert.deepEqual(JSON.parse(reply), { tagged: { label: 'Ok', value: toSpec(42) } });
      return JSON.stringify({ status: 'done', result: { value: toSpec(42) } });
    },
    async destroy(id) { destroyed.push(id); },
  };
  const oldHost = new ExpoEffects({});
  const oldSession = runSession(native, oldHost, 'old', update => oldUpdates.push(update), undefined, {}, oldController.signal);
  await oldStarted.promise;
  oldController.abort();
  assert.deepEqual(await promptly(oldSession), { status: 'cancelled' });
  const newHost = new ExpoEffects({ sdk: { run() { newStarted.resolve(); return sdkCall.promise; } } });
  const newSession = runSession(native, newHost, 'new', update => newUpdates.push(update));
  await newStarted.promise;
  oldCall.reject(new Error('Old read failed'));
  await new Promise(done => setImmediate(done));
  assert.equal(newHost.closed, false);
  assert.deepEqual(oldUpdates, []);
  assert.deepEqual(newUpdates, [{ status: 'effect', label: 'Expo' }]);
  assert.deepEqual(destroyed, [1]);
  sdkCall.resolve(42);
  assert.deepEqual(await newSession, { status: 'done', result: { value: toSpec(42) } });
  assert.equal(newHost.closed, true);
  assert.deepEqual(destroyed, [1, 2]);
});

test('callbacks return decoded constants synchronously and can omit events', async () => {
  class Resource { close() {} }
  const resource = new Resource();
  let returned;
  const host = new ExpoEffects({ sdk: { invoke(callback) { returned = callback('argument'); assert.equal(returned instanceof Promise, false); return 'done'; } } });
  const handle = host.encode(resource);
  await host.perform('Expo', { module: 'sdk', method: 'invoke', args: [{ expo_callback: 'decision', expo_return: { when: { expo_date: '2026-10-28T12:00:00Z' }, resource: handle, number: { expo_number: '0.5' } } }] });
  assert.ok(returned.when instanceof Date);
  assert.equal(returned.when.toISOString(), '2026-10-28T12:00:00.000Z');
  assert.equal(returned.resource, resource);
  assert.equal(returned.number, 0.5);
  assert.deepEqual((await host.nextEvent(0)).args, ['argument']);
  const silent = host.decode({ expo_callback: 'silent', expo_return: false, expo_emit: false });
  assert.equal(silent(), false);
  assert.equal(await host.nextEvent(0), null);
  assert.throws(() => host.decode({ expo_callback: 'bad', expo_reply: true, expo_return: 1 }), /Cannot combine/);
  assert.throws(() => host.decode({ expo_callback: 'bad', expo_reply: true, expo_emit: false }), /must emit/);
  await host.close();
});

test('deferred SDK call permits event, reply, then await without a VM deadlock', async () => {
  let completed = false, original;
  const host = new ExpoEffects({ sdk: { request(callback) {
    original = (async () => { const reply = await callback('approve'); assert.ok(reply instanceof Date); completed = true; return { approvedAt: reply }; })();
    return original;
  } } });
  const handle = await host.perform('Expo', { module: 'sdk', method: 'request', defer: true, args: [{ expo_callback: 'approval', expo_reply: true }] });
  assert.equal(host.handles.get(handle.expo_handle), original);
  const event = await host.perform('ExpoNextEvent', { timeoutMs: 1000 });
  assert.equal(completed, false);
  assert.equal(event.topic, 'approval');
  assert.deepEqual(event.args, ['approve']);
  assert.ok(Number.isSafeInteger(event.callback_token));
  assert.equal(await host.perform('ExpoReply', { token: event.callback_token, value: { expo_date: '2026-10-28T12:00:00Z' } }), null);
  assert.deepEqual(await host.perform('Expo', { handle: handle.expo_handle, method: '$await' }), { approvedAt: { expo_date: '2026-10-28T12:00:00.000Z' } });
  assert.equal(completed, true);
  assert.equal(host.replies.size, 0);
  assert.equal(host.deferred.size, 0);
  await assert.rejects(host.perform('ExpoReply', { token: event.callback_token, value: 1 }), /Unknown or settled/);
  await assert.rejects(host.perform('Expo', { handle: handle.expo_handle, method: '$await' }), /Unknown or consumed/);
  await host.close();
});

test('callback timeout removes tokens and invalid replies can be corrected', async () => {
  const host = new ExpoEffects({});
  const callback = host.decode({ expo_callback: 'reply', expo_reply: true, expo_timeout_ms: 10 });
  const pending = callback();
  const rejected = assert.rejects(pending, /timed out/);
  const event = await host.nextEvent(0);
  await assert.rejects(host.perform('ExpoReply', { token: event.callback_token, value: { expo_date: 'invalid' } }), /Invalid Expo date/);
  assert.equal(host.replies.size, 1);
  await rejected;
  assert.equal(host.replies.size, 0);
  await assert.rejects(host.perform('ExpoReply', { token: event.callback_token, value: 1 }), /Unknown or settled/);
  assert.throws(() => host.decode({ expo_callback: 'bad', expo_reply: true, expo_timeout_ms: -1 }), /timeout/);
  await host.close();
});

test('callback replies reject with decoded data and enforce single settlement', async () => {
  const host = new ExpoEffects({});
  const pending = host.decode({ expo_callback: 'reject', expo_reply: true })();
  const event = await host.nextEvent(0);
  await assert.rejects(host.perform('ExpoReply', { token: event.callback_token }), /exactly one/);
  await assert.rejects(host.perform('ExpoReply', { token: event.callback_token, value: 1, error: 'bad' }), /exactly one/);
  const rejected = assert.rejects(pending, value => value instanceof Date && value.getUTCFullYear() === 2026);
  await host.perform('ExpoReply', { token: event.callback_token, error: { expo_date: '2026-10-28' } });
  await rejected;
  await assert.rejects(host.perform('ExpoReply', { token: event.callback_token, value: null }), /Unknown or settled/);
  await host.close();
});

test('dropped callback events and pending-count limits reject unreachable replies', async () => {
  const host = new ExpoEffects({}, null, 2);
  const callback = host.decode({ expo_callback: 'reply', expo_reply: true });
  const first = callback();
  const dropped = assert.rejects(first, /event dropped/);
  host.emit('ordinary', [1]);
  host.emit('ordinary', [2]);
  await dropped;
  assert.equal(host.replies.size, 0);
  assert.equal(host.dropped, 1);
  await host.close();
  const bounded = new ExpoEffects({}, null, 1);
  const limited = bounded.decode({ expo_callback: 'bounded', expo_reply: true });
  const waiting = limited();
  const cancelled = assert.rejects(waiting, /closed/);
  await assert.rejects(limited(), /Too many pending/);
  assert.equal(bounded.replies.size, 1);
  await bounded.close();
  await cancelled;
});

test('close settles callback promises and an active deferred await', async () => {
  let saved;
  const host = new ExpoEffects({ sdk: { async request(callback) { saved = callback; return await callback('pending'); } } });
  const handle = await host.perform('Expo', { module: 'sdk', method: 'request', defer: true, args: [{ expo_callback: 'request', expo_reply: true }] });
  await host.nextEvent(0);
  const waiting = host.perform('Expo', { handle: handle.expo_handle, method: '$await' });
  const rejected = assert.rejects(waiting, /released|closed/);
  await host.close();
  await rejected;
  await assert.rejects(saved(), /closed/);
  assert.equal(host.replies.size, 0);
  assert.equal(host.deferred.size, 0);
  assert.equal(host.handles.size, 0);
});

test('deferred SDK rejection remains observed until its handle is awaited', async () => {
  const host = new ExpoEffects({ sdk: { fail() { return Promise.reject(new Error('SDK failure')); } } });
  const handle = await host.perform('Expo', { module: 'sdk', method: 'fail', defer: true });
  await new Promise(resolve => setImmediate(resolve));
  await assert.rejects(host.perform('Expo', { handle: handle.expo_handle, method: '$await' }), /SDK failure/);
  assert.equal(host.deferred.size, 0);
  await host.close();
});

test('released deferred promises dispose late SDK resources exactly once', async () => {
  for (const awaiting of [false, true]) {
    let resolve, disposed = 0;
    const promise = new Promise(done => { resolve = done; });
    const host = new ExpoEffects({ sdk: { open() { return promise; } } });
    const handle = await host.perform('Expo', { module: 'sdk', method: 'open', defer: true });
    let rejected;
    if (awaiting) rejected = assert.rejects(host.perform('Expo', { handle: handle.expo_handle, method: '$await' }), /released|closed/);
    if (awaiting) await host.close();
    else await host.perform('ExpoRelease', { handle: handle.expo_handle });
    if (rejected) await rejected;
    resolve({ close() { disposed++; } });
    await new Promise(done => setImmediate(done));
    assert.equal(disposed, 1);
    assert.equal(host.deferred.size, 0);
    await host.close();
    assert.equal(disposed, 1);
  }
});

test('Date arguments and results preserve Date values through EYG wrappers', async () => {
  let received;
  const host = new ExpoEffects({ sdk: { echo(value) { received = value; return value; } } });
  const date = new Date('2026-10-28T12:00:00.123Z');
  const wire = fromSpec(toSpec(host.encode({ nested: [date] })));
  const result = await host.perform('Expo', { module: 'sdk', method: 'echo', args: [wire] });
  assert.ok(received.nested[0] instanceof Date);
  assert.equal(received.nested[0].getTime(), date.getTime());
  assert.deepEqual(result, { nested: [{ expo_date: date.toISOString() }] });
  assert.equal(host.decode({ expo_date: '2026-10-28T13:00:00.123+01:00' }).getTime(), date.getTime());
  for (const value of ['not a date', '2026-02-30', '2026-01-01T24:00:00Z', 42, '']) {
    assert.throws(() => host.decode({ expo_date: value }), /Invalid Expo date/);
  }
  assert.throws(() => host.encode(new Date(NaN)), /Invalid Expo date/);
  await host.close();
});

test('pure synchronous EYG callbacks use an injected native evaluator and argument data', async () => {
  const requests = [];
  const host = new ExpoEffects({}, null, 1024, { pure(request) {
    const parsed = JSON.parse(request); requests.push(parsed);
    return JSON.stringify({ status: 'done', result: { value: toSpec(fromSpec(parsed.argument)[0] < 50) } });
  } });
  const callback = host.decode({ expo_callback: 'decision', expo_sync: '(args) -> { args }', expo_steps: 100, expo_emit: false });
  assert.equal(callback(10), true);
  assert.equal(callback(60), false);
  assert.equal(requests[0].max_steps, 100);
  assert.deepEqual(fromSpec(requests[1].argument), [60]);
  assert.equal(host.events.length, 0);
  await host.close();
  assert.equal(callback(1), undefined);
  assert.equal(requests.length, 2);
});

test('pure callback mode rejects ambiguous modes, budgets, cycles and native resources', async () => {
  const host = new ExpoEffects({}, null, 1024, { pure() { throw new Error('must not call'); } });
  for (const extra of [{ expo_return: true }, { expo_reply: true }, { expo_steps: 0 }, { expo_steps: 10001 }, { expo_sync: 42 }]) {
    assert.throws(() => host.decode({ expo_callback: 'x', expo_sync: '(args) -> { args }', ...extra }), /combine|budget|source/);
  }
  const callback = host.decode({ expo_callback: 'x', expo_sync: '(args) -> { args }' });
  const cycle = []; cycle.push(cycle);
  assert.throws(() => callback(cycle), /only data/);
  assert.throws(() => callback(new (class Resource {})()), /only data/);
  assert.throws(() => callback(new Uint8Array(4096)), /binary data exceeds size/);
  assert.throws(() => callback(new ArrayBuffer(4096)), /binary data exceeds size/);
  assert.equal(host.handles.size, 0);
  await host.close();
});

test('native pure callback failures are synchronous errors', async () => {
  for (const response of [{ status: 'error', error: 'StepLimit' }, { status: 'done', result: { break: { NoMatch: {} } } }]) {
    const host = new ExpoEffects({}, null, 1024, { pure: () => JSON.stringify(response) });
    const callback = host.decode({ expo_callback: 'x', expo_sync: '(args) -> { args }' });
    assert.throws(() => callback(), /Synchronous EYG callback failed/);
    await host.close();
  }
  const missing = new ExpoEffects({});
  assert.throws(() => missing.decode({ expo_callback: 'x', expo_sync: '(args) -> { args }' }), /no synchronous/);
  await missing.close();
});
