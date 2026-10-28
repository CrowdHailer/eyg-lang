// Fixture loading and evaluation use the pinned Gleam cache, not a JS cache port.
import {createInterface} from 'node:readline';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {resolve, dirname} from 'node:path';
import {handle as common, encodeValue, encodeBreak} from './oracle.mjs';

const root = resolve(process.env.EYG_ORACLE_ROOT || resolve(dirname(fileURLToPath(import.meta.url)), '../../../work/oracle-next-tui'));
const build = resolve(root, 'packages/gleam_cli/build/dev/javascript');
const load = path => import(pathToFileURL(resolve(build, path)).href);
const [runtime, json, codec, expression, cache, dict, cidV1] = await Promise.all([
  'eyg_cli/gleam.mjs', 'gleam_json/gleam/json.mjs', 'eyg_ir/eyg/ir/dag_json.mjs',
  'eyg_interpreter/eyg/interpreter/expression.mjs', 'eyg_hub/eyg/hub/cache.mjs',
  'gleam_stdlib/gleam/dict.mjs', 'multiformats/multiformats/cid/v1.mjs',
].map(load));
const cls = value => value?.constructor?.name;
const decode = source => {
  const result = json.parse(JSON.stringify(source), codec.decoder(null));
  if (cls(result) !== 'Ok') throw new Error('invalid fixture IR');
  return result[0];
};

function handle(request) {
  if (request.op === 'package_metadata' || request.op === 'hub_fixture') return common(request);
  const packages = common({...request, op: 'package_metadata'}).packages;
  let current = cache.empty();
  const entries = packages.map(p => ({...p, cid: cidV1.from_string(p.cid)[0][0]}));
  current.packages = dict.from_list(runtime.toList(entries.map(p => [p.name, new cache.Entry(p.version, p.cid, 1, 1, p.cid)])));
  current.releases = dict.from_list(runtime.toList(entries.map(p => [[p.name, p.version], p.cid])));
  for (const p of entries) current = cache.fetch_module_completed(current, p.cid, new runtime.Ok(decode(p.program)))[0];
  let result = expression.execute(decode(request.program), runtime.toList([]));
  result = cache.static_loop(result, current, expression.resume);
  return cls(result) === 'Ok' ? {value: encodeValue(result[0])} : {break: encodeBreak(result[0][0])};
}

for await (const line of createInterface({input: process.stdin, crlfDelay: Infinity})) {
  try { process.stdout.write(JSON.stringify(handle(JSON.parse(line))) + '\n'); }
  catch (error) { process.stdout.write(JSON.stringify({adapter_error: String(error), stack: error.stack}) + '\n'); }
}
