import test from 'node:test';
import assert from 'node:assert/strict';
import { ExpoEffects } from '../src/effects.mjs';
import { renderView } from '../src/views.mjs';

const createElement = (type, props, ...children) => ({ type, props, children });
const components = { Host() {}, Column() {}, Text() {}, Button() {}, Native: { $$typeof: Symbol.for('react.forward_ref') } };
const node = (component, fields = {}) => ({ module: 'ui', component, ...fields });

test('native descriptors compose nested components and text with root styling', () => {
  const host = new ExpoEffects({ ui: components });
  const tree = renderView(node('Host', { props: { style: { flex: 1 } }, children: [
    node('Column', { children: [node('Text', { children: 'Hello EYG 🌱' }), node('Text', { children: 42 }), null] }),
  ] }), host, createElement, { rootStyle: { height: 240 } });
  assert.equal(tree.type, components.Host);
  assert.deepEqual(tree.props.style, [{ height: 240 }, { flex: 1 }]);
  assert.equal(tree.children[0].type, components.Column);
  assert.equal(tree.children[0].props.style, undefined);
  assert.deepEqual(tree.children[0].children[0].children, ['Hello EYG 🌱']);
  assert.deepEqual(tree.children[0].children[1].children, [42]);
  assert.equal(tree.children[0].children[2], null);
});

test('view props decode callback functions and retain native object handles', async () => {
  class Resource { close() {} }
  const resource = new Resource();
  const host = new ExpoEffects({ ui: components });
  const handle = host.encode(resource);
  const tree = renderView(node('Button', { props: {
    resource: handle, onPress: { expo_callback: 'pressed', expo_return: true },
    options: { expo_object: [{ key: 'camelCase', value: { expo_number: '0.5' } }] },
  } }), host, createElement);
  assert.equal(tree.props.resource, resource);
  assert.deepEqual(tree.props.options, { camelCase: 0.5 });
  assert.equal(tree.props.onPress({ count: 3 }), true);
  assert.deepEqual(await host.nextEvent(0), { topic: 'pressed', args: [{ count: 3 }], dropped: 0 });
  await host.close();
});

test('refs are optional and guarded refs publish handles only for the active run', async () => {
  const host = new ExpoEffects({ ui: components });
  assert.equal(renderView(node('Text'), host, createElement).props.ref, undefined);
  let current = true;
  const events = [];
  const tree = renderView(node('Native', { id: 'camera', ref: true }), host, createElement, {
    current: () => current, emit: (topic, args) => events.push({ topic, args }),
  });
  const instance = { remove() {} };
  tree.props.ref(instance);
  assert.equal(events[0].topic, 'view:camera:ready');
  assert.equal(host.decode(events[0].args[0]), instance);
  current = false;
  tree.props.ref({ remove() {} });
  tree.props.ref(null);
  assert.equal(events.length, 1);
  assert.equal(host.handles.size, 1);
  assert.throws(() => renderView(node('Host'), host, createElement, { current: () => false }), /Closed/);
  await host.close();
});

test('explicit ref topics work for nested native components', () => {
  const host = new ExpoEffects({ ui: components });
  const topics = [];
  const tree = renderView(node('Host', { children: node('Native', { ref: 'nested-ready' }) }), host, createElement, {
    emit: topic => topics.push(topic),
  });
  tree.children[0].props.ref({});
  assert.deepEqual(topics, ['nested-ready']);
});

test('unknown modules and component paths fail before mounting', () => {
  const host = new ExpoEffects({ ui: components, invalid: { value: 7, object: {} } });
  for (const spec of [
    { module: 'missing', component: 'Host' }, { module: '__proto__', component: 'toString' },
    node('Missing'), node('__proto__.toString'),
    { module: 'invalid', component: 'value' }, { module: 'invalid', component: 'object' },
  ]) assert.throws(() => renderView(spec, host, createElement), /Unknown|Invalid/);
  assert.throws(() => renderView(node('Text', { props: [] }), host, createElement), /props/);
  assert.throws(() => renderView(node('Text', { children() {} }), host, createElement), /children/);
  assert.throws(() => renderView(node('Native', { ref: true }), host, createElement), /ref/);
});

test('view trees accept 64 component levels and reject deeper or cyclic input', () => {
  const host = new ExpoEffects({ ui: components });
  const chain = depth => {
    let child = node('Text', { children: 'leaf' });
    for (let i = 1; i < depth; i++) child = node('Column', { children: child });
    return child;
  };
  assert.doesNotThrow(() => renderView(chain(64), host, createElement));
  assert.throws(() => renderView(chain(65), host, createElement), /depth/);
  const cycle = node('Column');
  cycle.children = [cycle];
  assert.throws(() => renderView(cycle, host, createElement), /Cyclic/);
  const array = [];
  array.push(array);
  assert.throws(() => renderView(node('Column', { children: array }), host, createElement), /Cyclic/);
  for (const maxDepth of [0, -1, 65, Infinity, 0.5]) assert.throws(() => renderView(node('Text'), host, createElement, { maxDepth }), /limit/);
});
