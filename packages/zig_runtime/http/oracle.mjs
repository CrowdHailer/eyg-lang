// Actual next-tui touch_grass decoder/encoder and Gleam fetch transport.
// No HTTP behavior is implemented by this adapter.
import { pathToFileURL, fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
const root = resolve(process.env.EYG_ORACLE_ROOT || resolve(dirname(fileURLToPath(import.meta.url)), '../../../work/oracle-next-tui'));
const base = resolve(root, 'packages/gleam_cli/build/dev/javascript');
const load = p => import(pathToFileURL(resolve(base,p)).href);
const [runtime, values, dict, fetch, system, results, strings] = await Promise.all([
  'eyg_cli/gleam.mjs','eyg_interpreter/eyg/interpreter/value.mjs','gleam_stdlib/gleam/dict.mjs','touch_grass/touch_grass/fetch.mjs','loam/loam/system.mjs','gleam_stdlib/gleam/result.mjs','gleam_stdlib/gleam/string.mjs'
].map(load));
function decode(v) {
  if ('string' in v) return new values.String(v.string);
  if ('integer' in v) return new values.Integer(v.integer);
  if ('binary' in v) return new values.Binary(new runtime.BitArray(Uint8Array.from(Buffer.from(v.binary['/'].bytes,'base64'))));
  if ('list' in v) return new values.LinkedList(runtime.toList(v.list.map(decode)));
  if ('record' in v) return new values.Record(dict.from_list(runtime.toList(Object.entries(v.record).map(([k,v])=>[k,decode(v)]))));
  if ('tagged' in v) return new values.Tagged(v.tagged.label,decode(v.tagged.value));
  throw new Error('bad fixture');
}
function encode(v) {
  if (v instanceof values.Integer) return {integer:v.value};
  if (v instanceof values.String) return {string:v.value};
  if (v instanceof values.Binary) return {binary:{'/':{bytes:Buffer.from(v.value.rawBuffer).toString('base64').replace(/=+$/,'')}}};
  if (v instanceof values.LinkedList) return {list:Array.from(v.elements).map(encode)};
  if (v instanceof values.Record) return {record:Object.fromEntries(Array.from(dict.to_list(v.fields)).map(([k,v])=>[k,encode(v)]))};
  if (v instanceof values.Tagged) return {tagged:{label:v.label,value:encode(v.value)}};
  throw new Error('bad oracle response');
}
try {
  const request=fetch.decode(decode(JSON.parse(await new Response(Bun.stdin.stream()).text())));
  if (!request.isOk()) throw new Error('invalid request');
  const response=await system.run(system.fetch(request[0]));
  console.log(JSON.stringify(encode(fetch.encode(results.map_error(response,strings.inspect)))));
} catch(error) {
  console.log(JSON.stringify({oracle_exception:{name:error.name,message:error.message,string:String(error)}}));
}
