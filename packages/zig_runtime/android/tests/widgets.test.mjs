import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import { createRequire } from 'node:module';
import vm from 'node:vm';
const require = createRequire(import.meta.url);
const { transformSync } = require('@babel/core');
const { widgetsPlugin } = require('../node_modules/expo/node_modules/babel-preset-expo/build/plugins/widgets-plugin.js');
const source = fs.readFileSync(new URL('../src/widget-layout.mjs', import.meta.url), 'utf8');
const transformed = transformSync(source.replace('export function', 'function'), { configFile: false, babelrc: false, plugins: [widgetsPlugin] }).code;
const createElement = (type, props, ...children) => ({ type, props, children });
function layout() {
  const context = vm.createContext({ React: { createElement }, Text: 'Text', Column: 'Column', Row: 'Row', Box: 'Box', Button: 'Button' });
  vm.runInContext(`${transformed}; globalThis.layout = eygLayout;`, context);
  assert.equal(typeof context.layout, 'string', 'actual Expo compiler serializes the widget');
  return vm.runInContext(`(${context.layout})`, context);
}
const plain = value => JSON.parse(JSON.stringify(value));
test('actual Expo widget compiler produces a closed generic layout', () => {
  const render = layout();
  assert.deepEqual(plain(render({ tree: { component: 'Column', children: [{ component: 'Text', children: 'EYG history' }, { component: 'Text', props: { color: '#fff' }, children: '42 commits' }] } })), {
    type: 'Column', props: {}, children: [{ type: 'Text', props: {}, children: ['EYG history'] }, { type: 'Text', props: { color: '#fff' }, children: ['42 commits'] }],
  });
});
test('same precompiled layout supports custom notification sections', () => {
  const render = layout();
  const output = plain(render({ sections: { collapsed: { component: 'Text', children: 'Query complete' }, expanded: { component: 'Text', children: '42 commits' } } }));
  assert.equal(output.collapsed.children[0], 'Query complete');
  assert.equal(output.expanded.children[0], '42 commits');
});
test('widget layout rejects unsupported globals and deep trees', () => {
  const render = layout();
  assert.throws(() => render({ tree: { component: 'Function', children: 'danger' } }), /Unsupported/);
  let tree = { component: 'Text', children: 'leaf' };
  for (let i = 0; i < 33; i++) tree = { component: 'Column', children: [tree] };
  assert.throws(() => render({ tree }), /Invalid/);
});
