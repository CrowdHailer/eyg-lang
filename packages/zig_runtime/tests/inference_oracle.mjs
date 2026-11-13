// Calls the actual next-tui checker, including its runtime scope conversion.
import { createInterface } from 'node:readline';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve, dirname } from 'node:path';
const root = resolve(process.env.EYG_ORACLE_ROOT || resolve(dirname(fileURLToPath(import.meta.url)), '../../../work/oracle-next-tui'));
const build = resolve(root, 'packages/gleam_cli/build/dev/javascript');
const load = path => import(pathToFileURL(resolve(build, path)).href);
const [runtime,json,codec,infer,debug,computer,iface,expression,analysis,dict] = await Promise.all([
  'eyg_cli/gleam.mjs', 'gleam_json/gleam/json.mjs', 'eyg_ir/eyg/ir/dag_json.mjs',
  'eyg_analysis/eyg/analysis/inference/levels_j/contextual.mjs',
  'eyg_analysis/eyg/analysis/type_/binding/debug.mjs',
  'loam/loam/platform/computer.mjs', 'touch_grass/touch_grass/interface.mjs',
  'eyg_interpreter/eyg/interpreter/expression.mjs', 'morph/morph/analysis.mjs',
  'gleam_stdlib/gleam/dict.mjs',
].map(load));
function annotate(source, tree, depths, depth = 0) {
  tree[1] = source._native_node;
  depths.set(source._native_node, depth);
  if (source['0'] === 'a') {
    annotate(source.f, tree[0].func, depths, depth + 1);
    annotate(source.a, tree[0].argument, depths, depth + 1);
  } else if (source['0'] === 'l') {
    annotate(source.v, tree[0].definition, depths, depth + 1);
    annotate(source.t, tree[0].body, depths, depth + 1);
  } else if (source['0'] === 'f') annotate(source.b, tree[0].body, depths, depth + 1);
}
export function check(request) {
  const input = request.program;
  let scope = runtime.toList([]);
  for (const entry of request.scope || []) {
    const parsed = json.parse(JSON.stringify(entry.program), codec.decoder(null))[0];
    const result = expression.execute(parsed, scope);
    if (result.constructor.name !== 'Ok') throw new Error('binding program failed');
    scope = runtime.toList([[entry.name, result[0]], ...scope]);
  }
  const tree = json.parse(JSON.stringify(input), codec.decoder(null))[0];
  const depths = new Map();
  annotate(input, tree, depths);
  const context = infer.with_effects(infer.pure(), iface.types(computer.effects()));
  const [bindings, env] = analysis.env_to_tenv(scope, null);
  context.level = 0; context.bindings = bindings; context.env = env;
  const checked = infer.check_with_references(context, dict.new$(), tree);
  const errors = Array.from(infer.all_errors(checked));
  const info = {};
  for (const id of depths.keys()) {
    const found = infer.info_at(checked, id)[0];
    if (!found) continue;
    info[id] = {
      type: debug.mono(found.type_),
      problem: found.status.constructor.name === 'Error' ? debug.reason(found.status[0]) : null,
      effect: debug.effect(found.effect),
    };
  }
  return {
    root_type: debug.mono(infer.type_(checked)),
    error_count: errors.filter(([id,e]) => e.constructor.name !== 'MissingReference' && !(e.constructor.name === 'Todo' && depths.get(id) < 2)).length,
    loading_count: errors.filter(([,e]) => e.constructor.name === 'MissingReference').length,
    info,
  };
}
const lines = createInterface({ input: process.stdin });
for await (const line of lines) {
  try { console.log(JSON.stringify(check(JSON.parse(line)))); }
  catch (error) { console.log(JSON.stringify({ error: String(error) })); }
}
