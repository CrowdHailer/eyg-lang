// Host integration: actual Zig C ABI + production JS session/effects, fixture SDK.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { resolve } from 'node:path';
import { parseArgs } from 'node:util';
import { ExpoEffects, fromSpec } from '../src/effects.mjs';
import { runSession } from '../src/session.mjs';

class NativeProxy {
  constructor(library) {
    this.pending = new Map();
    this.sequence = 0;
    this.stderr = '';
    this.child = spawn(process.env.PYTHON ?? 'python3', [
      fileURLToPath(new URL('../scripts/native-proxy.py', import.meta.url)), library,
    ], { stdio: ['pipe', 'pipe', 'pipe'] });
    this.exit = new Promise((done, reject) => {
      this.child.once('error', reject);
      this.child.once('close', (code, signal) => {
        const error = new Error(`Native proxy exited (${signal ?? code}): ${this.stderr}`);
        for (const pending of this.pending.values()) pending.reject(error);
        this.pending.clear();
        if (code === 0) done(); else reject(error);
      });
    });
    this.exit.catch(() => {});
    this.child.stderr.on('data', data => { this.stderr = (this.stderr + data).slice(-8192); });
    createInterface({ input: this.child.stdout }).on('line', line => {
      const reply = JSON.parse(line);
      const pending = this.pending.get(reply.id);
      if (!pending) throw new Error(`Unexpected native proxy response ${reply.id}`);
      this.pending.delete(reply.id);
      if (reply.ok) pending.resolve(reply.value); else pending.reject(new Error(reply.error));
    });
  }

  request(method, ...args) {
    const id = ++this.sequence;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => {
        this.child.kill();
        reject(new Error(`Native proxy timed out at ${method}`));
      }, 5000);
      this.pending.set(id, {
        resolve: value => { clearTimeout(timer); resolve(value); },
        reject: error => { clearTimeout(timer); reject(error); },
      });
      this.child.stdin.write(JSON.stringify({ id, method, args }) + '\n', error => {
        if (error) this.pending.get(id)?.reject(error);
      });
    });
  }

  create() { return this.request('create'); }
  evaluate(id, source) { return this.request('evaluate', id, source); }
  resume(id, reply) { return this.request('resume', id, reply); }
  destroy(id) { return this.request('destroy', id); }
  stats() { return this.request('stats'); }
  async close() { this.child.stdin.end(); await this.exit; }
}

const unwrap = 'let unwrap = match { Ok(value) -> { value } Error(reason) -> { !never(perform Abort(reason)) } }';

function sourceFor(steps) {
  const lines = [unwrap, 'let resource = unwrap(perform Expo({module: "FakeSDK", method: "acquireResource"}))'];
  for (const [i, step] of steps.entries()) {
    lines.push(`
let pending${i} = unwrap(perform Expo({
  module: "FakeSDK", method: "asyncDecide", defer: True({}),
  args: [{expo_object: [{key: "requestId", value: ${step.request}}, {key: "score", value: ${step.score}}]},
    {expo_callback: "${step.topic}", expo_reply: True({}), expo_timeout_ms: 2000}]
}))
let event${i} = unwrap(perform ExpoNextEvent({timeout_ms: 2000}))
let reply${i} = unwrap(perform ExpoReply({token: event${i}.callback_token, value: ${step.accepted ? 'True' : 'False'}({})}))
let result${i} = unwrap(perform Expo({expo_handle: pending${i}.expo_handle, method: "$await"}))
let request_id${i} = unwrap(perform Expo({object: result${i}, method: "requestId", get: True({})}))`);
  }
  lines.push('[' + steps.map((_, i) => `{event: event${i}, result: result${i}, request_id: request_id${i}}`).join(', ') + ']');
  return lines.join('\n');
}

function fixture() {
  const state = { allocated: 0, removed: 0, started: 0, completed: 0, cancelled: 0, operations: [] };
  const sdk = {
    acquireResource() {
      state.allocated++;
      let removed = false;
      return { remove() { assert.equal(removed, false); removed = true; state.removed++; } };
    },
    asyncDecide(request, callback) {
      state.started++;
      const operation = (async () => {
        // Vary asynchronous delivery without wall-clock timers or a phone.
        if (request.requestId % 2) await new Promise(done => setImmediate(done));
        else await Promise.resolve();
        try {
          const accepted = await callback(request);
          assert.equal(typeof accepted, 'boolean');
          state.completed++;
          return { requestId: request.requestId, accepted, score: accepted ? request.score : -request.score };
        } catch (error) {
          state.cancelled++;
          throw error;
        }
      })();
      // The host observes the SDK promise; this also lets the test check cleanup.
      state.operations.push(operation.then(() => 'completed', () => 'cancelled'));
      return operation;
    },
  };
  return { host: new ExpoEffects({ FakeSDK: sdk }), state };
}

function assertClosed(host, state) {
  assert.equal(host.closed, true);
  assert.equal(host.handles.size, 0);
  assert.equal(host.deferred.size, 0);
  assert.equal(host.replies.size, 0);
  assert.equal(host.events.length, 0);
  assert.equal(host.waiters.length, 0);
  assert.equal(state.removed, state.allocated);
}

const { values } = parseArgs({ options: {
  library: { type: 'string', default: fileURLToPath(new URL('../work/libeyg_android_host.so', import.meta.url)) },
  cases: { type: 'string', default: '32' },
} });
const cases = Number(values.cases);
assert.ok(Number.isSafeInteger(cases) && cases > 0, '--cases must be a positive integer');
const native = new NativeProxy(resolve(values.library));
let seed = 0x455947;
const random = n => { seed = (Math.imul(seed, 1664525) + 1013904223) >>> 0; return seed % n; };
let cycles = 0;
let approvals = 0;
let denials = 0;
try {
  for (let index = 0; index < cases; index++) {
    const steps = Array.from({ length: 1 + random(3) }, (_, step) => ({
      request: 1 + random(100000), score: random(200001) - 100000,
      accepted: random(2) === 1, topic: `decision_${index}_${step}`,
    }));
    const { host, state } = fixture();
    const labels = [];
    const source = sourceFor(steps);
    const response = await runSession(native, host, source, update => labels.push(update.label), undefined, { packages: {} });
    assert.equal(response.status, 'done', `${JSON.stringify(response)}\n${source}`);
    assert.ok(response.result?.value, `${JSON.stringify(response)}\n${source}`);
    assert.deepEqual(fromSpec(response.result.value), steps.map((step, i) => ({
      event: { topic: step.topic, args: [{ requestId: step.request, score: step.score }], dropped: 0, callback_token: i + 1 },
      result: { requestId: step.request, accepted: step.accepted, score: step.accepted ? step.score : -step.score },
      request_id: step.request,
    })), `seed 0x455947 program ${index}`);
    assert.deepEqual(labels, ['Expo', ...steps.flatMap(() => ['Expo', 'ExpoNextEvent', 'ExpoReply', 'Expo', 'Expo'])]);
    assert.deepEqual(await Promise.all(state.operations), steps.map(() => 'completed'));
    assert.equal(state.started, steps.length);
    assert.equal(state.completed, steps.length);
    assert.equal(state.cancelled, 0);
    assertClosed(host, state);
    assert.deepEqual(await native.stats(), { created: index + 1, destroyed: index + 1, live: 0 });
    cycles += steps.length;
    approvals += steps.filter(step => step.accepted).length;
    denials += steps.filter(step => !step.accepted).length;
  }
  assert.ok(approvals > 0 && denials > 0, 'generated cases must cover both decisions');

  const { host, state } = fixture();
  let cancelled = false;
  const labels = [];
  const response = await runSession(native, host, sourceFor([{ request: 2, score: 42, accepted: true, topic: 'cancel' }]), update => {
    labels.push(update.label);
    if (update.label === 'ExpoNextEvent') cancelled = true;
  }, () => cancelled, { packages: {} });
  assert.deepEqual(response, { status: 'cancelled' });
  assert.deepEqual(labels, ['Expo', 'Expo', 'ExpoNextEvent']);
  assert.deepEqual(await Promise.all(state.operations), ['cancelled']);
  // Cancellation detaches promptly; allow asynchronous SDK disposal to finish.
  await new Promise(done => setImmediate(done));
  assert.equal(state.completed, 0);
  assert.equal(state.cancelled, 1);
  assertClosed(host, state);
  assert.deepEqual(await native.stats(), { created: cases + 1, destroyed: cases + 1, live: 0 });
  console.log(JSON.stringify({ seed: '0x455947', generatedPrograms: cases, callbackCycles: cycles,
    approvals, denials, actualZigVm: 'passed', jsSessionEffects: 'passed',
    camelCaseSdkOptionsAndResults: 'passed', suspendedVmCancellation: 'passed', nativeSessionsDestroyed: cases + 1,
    sdk: 'deterministic fixture; no device or hardware validation' }));
} finally {
  await native.close();
}
