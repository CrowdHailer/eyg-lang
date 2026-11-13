// Thin calls into the pinned implementation's pure computer-effect contracts.
import {createInterface} from 'node:readline';
import {fileURLToPath, pathToFileURL} from 'node:url';
import {resolve, dirname} from 'node:path';
import {encodeValue, encodeBreak} from './oracle.mjs';

const root = resolve(process.env.EYG_ORACLE_ROOT || resolve(dirname(fileURLToPath(import.meta.url)), '../../../work/oracle-next-tui'));
const build = resolve(root, 'packages/gleam_cli/build/dev/javascript');
const load = path => import(pathToFileURL(resolve(build, path)).href);
const [runtime, values, dict, source, eygParse, json, sign, computer, eddsa, gleamJson, irCodec, expression, breaks, system] = await Promise.all([
  'eyg_cli/gleam.mjs', 'eyg_interpreter/eyg/interpreter/value.mjs',
  'gleam_stdlib/gleam/dict.mjs', 'loam/loam/source.mjs',
  'touch_grass/touch_grass/eyg_parse.mjs', 'touch_grass/touch_grass/decode_json.mjs',
  'touch_grass/touch_grass/cryptography/sign.mjs', 'loam/loam/platform/computer.mjs',
  'kryptos/kryptos/eddsa.mjs',
  'gleam_json/gleam/json.mjs', 'eyg_ir/eyg/ir/dag_json.mjs',
  'eyg_interpreter/eyg/interpreter/expression.mjs', 'eyg_interpreter/eyg/interpreter/break.mjs',
  'loam/loam/system.mjs',
].map(load));

function decode(v) {
  if ('integer' in v) return new values.Integer(v.integer);
  if ('string' in v) return new values.String(v.string);
  if ('binary' in v) return new values.Binary(runtime.toBitArray([Uint8Array.from(Buffer.from(v.binary['/'].bytes, 'base64'))]));
  if ('record' in v) return new values.Record(dict.from_list(runtime.toList(Object.entries(v.record).map(([k, v]) => [k, decode(v)]))));
  if ('tagged' in v) return new values.Tagged(v.tagged.label, decode(v.tagged.value));
  if ('list' in v) return new values.LinkedList(runtime.toList(v.list.map(decode)));
  throw new Error('not a data fixture');
}

async function handle(request) {
  if (request.program) {
    const decoded = gleamJson.parse(JSON.stringify(request.program), irCodec.decoder(null));
    if (decoded.constructor.name !== 'Ok') return {decode_error: true};
    let result = expression.execute(decoded[0], runtime.toList([]));
    for (let budget = 1000; budget > 0; --budget) {
      if (result.constructor.name === 'Ok') return {value: encodeValue(result[0])};
      const reason = result[0][0];
      if (!(reason instanceof breaks.UnhandledEffect)) return {break: encodeBreak(reason)};
      const cast = computer.cast(reason.label, reason.value);
      if (cast.constructor.name === 'Error') return {break: encodeBreak(cast[0])};
      const reply = await system.run(computer.extrinsic(cast[0], source.Origin$Inline$const));
      result = expression.resume(reply, result[0][2], result[0][3]);
    }
    throw new Error('pure-effect program exhausted its effect budget');
  }
  const lift = decode(request.lift);
  if (request.label !== 'derive-public-key') {
    const cast = computer.cast(request.label, lift);
    if (cast.constructor.name === 'Error') return {break: encodeBreak(cast[0])};
    if (request.cast_only) return {valid: true};
  }
  if (request.label === 'DecodeJSON') return {value: encodeValue(json.sync(lift.value))};
  if (request.label === 'EYGParse') return {value: encodeValue(eygParse.encode(source.parse(lift.value, source.Origin$Inline$const)))};
  if (request.label === 'Sign') {
    const cast = sign.decode(lift);
    if (cast.constructor.name === 'Error') return {break: encodeBreak(cast[0])};
    return {value: encodeValue(sign.encode(computer.sign(cast[0])))};
  }
  if (request.label === 'derive-public-key') {
    const imported = eddsa.from_bytes(eddsa.Curve$Ed25519$const, lift.value);
    if (imported.constructor.name === 'Error') throw new Error('oracle rejected generated private key');
    return encodeValue(new values.Binary(eddsa.public_key_to_bytes(imported[0][1])));
  }
  throw new Error(`unknown pure effect ${request.label}`);
}

for await (const line of createInterface({input: process.stdin, crlfDelay: Infinity})) {
  try { process.stdout.write(JSON.stringify(await handle(JSON.parse(line))) + '\n'); }
  catch (error) { process.stdout.write(JSON.stringify({adapter_error: String(error)}) + '\n'); }
}
