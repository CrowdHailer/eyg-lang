// The production effect host calls an actual isolated Zig VM synchronously.
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { ExpoEffects } from '../src/effects.mjs';
const library = process.argv[2] ?? 'work/libeyg_android_host.so';
let calls = 0;
const pure = request => {
  calls++;
  const result = spawnSync(process.env.PYTHON ?? 'python3', [fileURLToPath(new URL('../scripts/pure-native.py', import.meta.url)), library], { input: request, encoding: 'utf8' });
  assert.equal(result.status, 0, result.stderr);
  return result.stdout;
};
const host = new ExpoEffects({}, null, 1024, { pure });
const source = '(args) -> { let score = match !list_pop(args) { Ok(item) -> { item.head } Error(_) -> { 0 } } match !int_compare(score, 50) { Lt(_) -> { True({}) } | (_) -> { False({}) } } }';
const callback = host.decode({ expo_callback: 'decision', expo_sync: source, expo_steps: 1000 });
for (let score = 0; score < 100; score += 3) assert.equal(callback(score), score < 50);
assert.equal((await host.nextEvent(0)).topic, 'decision');
const data = host.decode({ expo_callback: 'identity', expo_sync: '(args) -> { args }', expo_emit: false });
assert.deepEqual(data({ name: 'history', approved: true, score: 0.75 }), [{ name: 'history', approved: true, score: 0.75 }]);
const app = (f, a) => ({ 0: 'a', f, a });
const variable = name => ({ 0: 'v', l: name });
const select = (name, value) => app({ 0: 'g', l: name }, value);
const camelIR = { 0: 'f', l: 'args', b: select('canAskAgain', select('head', app({ 0: 'b', l: 'list_pop' }, variable('args')))) };
// list_pop returns Ok(record); unwrap using a tagged match before selecting.
camelIR.b = app(app(app({ 0: 'm', l: 'Ok' }, { 0: 'f', l: 'item', b: select('canAskAgain', select('head', variable('item'))) }), { 0: 'n' }), app({ 0: 'b', l: 'list_pop' }, variable('args')));
const foreign = host.decode({ expo_callback: 'foreign', expo_sync: JSON.stringify(camelIR), expo_emit: false });
assert.equal(foreign({ canAskAgain: true }), true);
assert.throws(() => host.decode({ expo_callback: 'effect', expo_sync: '(args) -> { perform Expo(args) }' })('no'), /PureEffectsNotAllowed/);
assert.throws(() => host.decode({ expo_callback: 'ref', expo_sync: '(args) -> { import "missing" }' })(), /PureReferencesNotAllowed/);
assert.throws(() => host.decode({ expo_callback: 'loop', expo_sync: '(args) -> { let loop = (self) -> { self(self) } loop(loop) }', expo_steps: 100 })(), /StepLimit/);
assert.throws(() => host.decode({ expo_callback: 'small', expo_sync: '(args) -> { args }', expo_steps: 1 })(), /StepLimit/);
assert.throws(() => host.decode({ expo_callback: 'bad', expo_sync: source, expo_steps: 10001 }), /step budget/);
assert.throws(() => host.decode({ expo_callback: 'bad', expo_sync: source, expo_return: true }), /combine/);
assert.throws(() => data(new (class Resource {})()), /only data/);
const grow = n => '(args) -> { let twice = (s) -> { !string_append(s, s) } ' + 'twice('.repeat(n) + '"x"' + ')'.repeat(n) + ' }';
assert.throws(() => host.decode({ expo_callback: 'memory', expo_sync: grow(23), expo_emit: false })(), /OutOfMemory/);
assert.throws(() => host.decode({ expo_callback: 'output', expo_sync: grow(17), expo_emit: false })(), /PureOutputTooLarge/);
assert.throws(() => host.decode({ expo_callback: 'recursive-equality', expo_sync: '(args) -> { !equal(args, args) }' })(), /PureBuiltinNotBounded/);
for (const builtin of ['string_split', 'string_split_once', 'string_replace']) {
  assert.throws(() => host.decode({ expo_callback: 'search', expo_sync: `(args) -> { !${builtin} }` })(), /PureBuiltinNotBounded/);
}
const before = calls;
await host.close();
assert.equal(callback(42), undefined);
assert.equal(calls, before);
assert.equal(host.handles.size, 0);
console.log(JSON.stringify({ realNativeSynchronousCallbacks: calls, argumentDependentDecisions: 34, effectsForbidden: true, referencesForbidden: true, stepBudget: 'passed', closedHost: 'passed' }));
