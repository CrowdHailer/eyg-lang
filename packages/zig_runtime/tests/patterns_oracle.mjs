// Calls the compiled, pinned morph implementation; no pattern recognition is
// implemented in this adapter.
import { createInterface } from 'node:readline';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(process.env.EYG_ORACLE_ROOT || resolve(here, '../../../work/oracle-next-tui'));
const build = resolve(root, 'packages/gleam_cli/build/dev/javascript');
const load = path => import(pathToFileURL(resolve(build, path)).href);
const [runtime, json, codec, editable] = await Promise.all([
  'morph/gleam.mjs', 'gleam_json/gleam/json.mjs',
  'eyg_ir/eyg/ir/dag_json.mjs', 'morph/morph/editable.mjs',
].map(load));
const list = xs => runtime.toList(xs);
function decode(program) {
  const parsed = json.parse(JSON.stringify(program), codec.decoder(null));
  if (parsed.constructor.name !== 'Ok') throw new Error('bad oracle IR fixture');
  return parsed[0];
}
function handle(request) {
  if (request.op === 'gather') {
    const ast = editable.from_annotated(decode({'0':'f', l:request.label, b:request.body}));
    const pattern = Array.from(ast[0])[0];
    return pattern instanceof editable.Bind
      ? {label:pattern[0],destructured:false,fields:[]}
      : {label:request.label,destructured:true,fields:Array.from(pattern[0]).map(([name,variable]) => ({name,variable}))};
  }
  const p = request.pattern;
  const pattern = p.destructured ? new editable.Destructure(list(p.fields.map(f => [f.name,f.variable]))) : new editable.Bind(p.label);
  const body = editable.from_annotated(decode(request.body));
  const result = editable.to_annotated(new editable.Function(list([pattern]), body), list([]));
  return JSON.parse(codec.to_string(result));
}
for await (const line of createInterface({input:process.stdin})) {
  try { process.stdout.write(JSON.stringify(handle(JSON.parse(line)))+'\n'); }
  catch (error) { process.stdout.write(JSON.stringify({adapter_error:String(error)})+'\n'); }
}
