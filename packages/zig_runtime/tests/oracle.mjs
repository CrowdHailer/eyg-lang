// Thin adapter around the pinned, compiled Gleam implementation. No EYG or TUI
// semantics are reimplemented here. This intentionally lives outside the oracle.
import { createInterface } from 'node:readline';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { resolve, dirname } from 'node:path';
import { isDeepStrictEqual } from 'node:util';
import { createHash } from 'node:crypto';

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(process.env.EYG_ORACLE_ROOT || resolve(here, '../../../work/oracle-next-tui'));
const build = resolve(root, 'packages/gleam_cli/build/dev/javascript');
const load = (path) => import(pathToFileURL(resolve(build, path)).href);
const [runtime, json, dict, codec, expression, values, breaks, state, view, backend,
  geometry, buffer, execute, cache, origin, sandbox, lexer, token, parser, ir, input, sourceParser,
  cidV1, hashes, response, hubSchema, publisher, simpleDebug, sourceLocation] = await Promise.all([
  'eyg_cli/gleam.mjs', 'gleam_json/gleam/json.mjs', 'gleam_stdlib/gleam/dict.mjs',
  'eyg_ir/eyg/ir/dag_json.mjs', 'eyg_interpreter/eyg/interpreter/expression.mjs',
  'eyg_interpreter/eyg/interpreter/value.mjs', 'eyg_interpreter/eyg/interpreter/break.mjs',
  'eyg_cli/eyg/cli/tui/state.mjs', 'eyg_cli/eyg/cli/tui/view.mjs',
  'etui/etui/backend.mjs', 'etui/etui/geometry.mjs', 'etui/etui/buffer.mjs',
  'loam/loam/execute.mjs', 'eyg_hub/eyg/hub/cache.mjs', 'ogre/ogre/origin.mjs',
  'loam/loam/sandbox.mjs',
  'eyg_parser/eyg/parser/lexer.mjs', 'eyg_parser/eyg/parser/token.mjs', 'eyg_parser/eyg/parser/parser.mjs',
  'eyg_ir/eyg/ir/tree.mjs',
  'etui/etui/input.mjs',
  'eyg_parser/eyg/parser.mjs',
  'multiformats/multiformats/cid/v1.mjs', 'multiformats/multiformats/hashes.mjs',
  'gleam_http/gleam/http/response.mjs',
  'eyg_hub/eyg/hub/schema.mjs', 'eyg_hub/eyg/hub/publisher.mjs',
  'eyg_interpreter/eyg/interpreter/simple_debug.mjs',
  'loam/loam/source.mjs',
].map(load));

const list = (items) => runtime.toList(items);
const array = (items) => Array.from(items);
const cls = (x) => x?.constructor?.name;
const color = (c) => cls(c) === 'Default' ? null : cls(c) === 'Indexed' ? c[0] : [c[0], c[1], c[2]];

export function encodeValue(v) {
  if (v instanceof values.Integer) return { integer: v.value };
  if (v instanceof values.String) return { string: v.value };
  if (v instanceof values.Binary) return { binary: { '/': { bytes: Buffer.from(v.value.rawBuffer).toString('base64').replace(/=+$/, '') } } };
  if (v instanceof values.LinkedList) return { list: array(v.elements).map(encodeValue) };
  if (v instanceof values.Record) return { record: Object.fromEntries(array(dict.to_list(v.fields)).map(([k,v]) => [k, encodeValue(v)])) };
  if (v instanceof values.Tagged) return { tagged: { label: v.label, value: encodeValue(v.value) } };
  if (v instanceof values.Closure || v instanceof values.Partial) return { function: true };
  throw new Error(`unknown oracle value ${cls(v)}`);
}

function decodeValue(v) {
  if ('integer' in v) return new values.Integer(v.integer);
  if ('string' in v) return new values.String(v.string);
  if ('binary' in v) return new values.Binary(runtime.toBitArray([Uint8Array.from(Buffer.from(v.binary['/'].bytes, 'base64'))]));
  if ('list' in v) return new values.LinkedList(list(v.list.map(decodeValue)));
  if ('record' in v) return new values.Record(dict.from_list(list(Object.entries(v.record).map(([k,v]) => [k, decodeValue(v)]))));
  if ('tagged' in v) return new values.Tagged(v.tagged.label, decodeValue(v.tagged.value));
  throw new Error(`not a fixture value: ${JSON.stringify(v)}`);
}

export function encodeBreak(reason) {
  if (reason instanceof breaks.UndefinedVariable) return { UndefinedVariable: reason.variable };
  if (reason instanceof breaks.UndefinedBuiltin) return { UndefinedBuiltin: reason.identifier };
  if (reason instanceof breaks.Vacant) return { NotImplemented: '' };
  if (reason instanceof breaks.NotAFunction) return { NotAFunction: encodeValue(reason.value) };
  if (reason instanceof breaks.NoMatch) return { NoMatch: encodeValue(reason.term) };
  if (reason instanceof breaks.MissingField) return { MissingField: reason.label };
  if (reason instanceof breaks.IncorrectTerm) return { IncorrectTerm: { expected: reason.expected, got: encodeValue(reason.got) } };
  if (reason instanceof breaks.UnhandledEffect) return { UnhandledEffect: { label: reason.label, value: encodeValue(reason.value) } };
  if (reason instanceof breaks.Unrepresentable) return { Unrepresentable: { builtin: reason.builtin, args: array(reason.args).map(encodeValue) } };
  if (reason instanceof breaks.UndefinedReference) return { UndefinedReference: JSON.parse(codec.to_string([new ir.Reference(reason.reference), null])) };
  throw new Error(`unknown oracle break ${cls(reason)}`);
}

export function evaluate(request) {
  const decoded = json.parse(JSON.stringify(request.program), codec.decoder(null));
  if (cls(decoded) !== 'Ok') return { decode_error: true };
  let result = expression.execute(decoded[0], list([]));
  const observed = [];
  for (const effect of request.effects || []) {
    const reason = result[0]?.[0];
    if (cls(result) !== 'Error' || !(reason instanceof breaks.UnhandledEffect)) {
      return { effect_mismatch: { expected: effect, got: cls(result) } };
    }
    const got = { label: reason.label, lift: encodeValue(reason.value) };
    observed.push(got);
    if (!isDeepStrictEqual(got, {label: effect.label, lift: effect.lift})) {
      return { effect_mismatch: { expected: effect, got } };
    }
    result = expression.resume(decodeValue(effect.reply), result[0][2], result[0][3]);
  }
  return cls(result) === 'Ok' ? { value: encodeValue(result[0]) } : { break: encodeBreak(result[0][0]) };
}

export function pretty(request) {
  const meta = request.meta === 'repl' ? new sourceLocation.Location(sourceLocation.Origin$Repl$const, sourceLocation.Source$Json$const) : undefined;
  const decoded = json.parse(JSON.stringify(request.program), codec.decoder(meta));
  if (cls(decoded) !== 'Ok') return {decode_error:true};
  const result = expression.execute(decoded[0], list([]));
  return cls(result) === 'Ok' ? {text:simpleDebug.render(result[0], request.width ?? 80)} : {break:encodeBreak(result[0][0])};
}

// Source annotations are observable inside captured continuations. Ask the
// actual loam parser to retain them; this adapter only transports its nodes.
export function prettySource(request) {
  const origin = request.origin === 'inline' ? sourceLocation.Origin$Inline$const
    : request.origin === 'pipe' ? sourceLocation.Origin$Pipe$const
    : request.origin === 'repl' ? sourceLocation.Origin$Repl$const
    : new sourceLocation.Disk(request.path ?? '/module.eyg');
  const parsed = sourceLocation.parse(request.source, origin);
  if (cls(parsed) !== 'Ok') return {parse_error:true};
  if (request.op === 'source_parse') {
    const withSpans = (node) => {
      const [expression, location] = node;
      const json = JSON.parse(codec.to_string(node));
      if (location.source instanceof sourceLocation.Text) json._span = location.source.span;
      if (expression instanceof ir.Apply) {
        json.f = withSpans(expression.func);
        json.a = withSpans(expression.argument);
      } else if (expression instanceof ir.Lambda) json.b = withSpans(expression.body);
      else if (expression instanceof ir.Let) {
        json.v = withSpans(expression.definition);
        json.t = withSpans(expression.body);
      }
      return json;
    };
    return {program:withSpans(parsed[0])};
  }
  const result = expression.execute(parsed[0], list([]));
  return cls(result) === 'Ok' ? {text:simpleDebug.render(result[0], request.width ?? 80)} : {break:encodeBreak(result[0][0])};
}

function frame(current, width, height) {
  const rendered = view.render(current, geometry.rect_new(0, 0, width, height));
  const cells = [];
  for (let y = 0; y < height; ++y) for (let x = 0; x < width; ++x) {
    const cell = buffer.get_cell(rendered, new geometry.Position(x, y));
    cells.push({
      symbol: buffer.cell_symbol(cell),
      width: buffer.is_continuation(cell) ? 0 : cell.content.width,
      fg: color(cell.style.fg), bg: color(cell.style.bg),
      modifiers: cell.style.modifier.bits, sub_modifiers: cell.style.sub_modifier.bits,
      underline_color: color(cell.style.underline_color), link: cell.link,
    });
  }
  return { width, height, cells };
}

function fixturePackages(request) {
  const packages = [];
  for (const [name, fixture] of Object.entries(request.packages || {})) {
    const decoded = json.parse(JSON.stringify(fixture.program), codec.decoder(null));
    if (cls(decoded) !== 'Ok') throw new Error(`invalid package fixture ${name}`);
    const bytes = codec.to_block(decoded[0]);
    const digest = createHash('sha256').update(Buffer.from(bytes.rawBuffer)).digest();
    const cid = new cidV1.Cid(297, new hashes.Multihash(hashes.Algorithm$Sha256$const, runtime.toBitArray([new Uint8Array(digest)])));
    const cidText = cidV1.to_string(cid);
    if (fixture.cid && fixture.cid !== cidText) throw new Error(`package fixture CID mismatch ${name}: ${fixture.cid} != ${cidText}`);
    packages.push({name, version: fixture.version ?? 1, cid, cidText, bytes, program: fixture.program});
  }
  const initial = cache.empty();
  initial.packages = dict.from_list(list(packages.map(p => [p.name, new cache.Entry(p.version, p.cid, 1, 1, p.cid)])));
  initial.releases = dict.from_list(list(packages.map(p => [[p.name, p.version], p.cid])));
  return {initial, packages};
}

function httpHubFixture(request) {
  const fixtures = fixturePackages(request).packages;
  const modules = {}, entries = [];
  for (const [index, p] of fixtures.entries()) {
    modules[p.cidText] = Buffer.from(p.bytes.rawBuffer).toString('base64');
    const payload = JSON.stringify({sequence:p.version,previous:null,signatory:{'/':p.cidText},key:'fixture-key',type:'release',content:{package:p.name,version:p.version,module:{'/':p.cidText}}});
    if (cls(json.parse(payload, publisher.decoder())) !== 'Ok') throw new Error('invalid fixture publisher entry');
    const digest = createHash('sha256').update(payload).digest();
    const entryCid = cidV1.to_string(new cidV1.Cid(297, new hashes.Multihash(hashes.Algorithm$Sha256$const, runtime.toBitArray([new Uint8Array(digest)]))));
    entries.push({cursor:index+1,cid:{'/':entryCid},payload,entity:{'/':p.cidText},sequence:p.version,type:'release'});
  }
  const ledger = {entries};
  if (cls(json.parse(JSON.stringify(ledger), hubSchema.pull_response_decoder())) !== 'Ok') throw new Error('invalid fixture ledger');
  return {ledger,modules};
}

export function tui(request) {
  let width = request.width ?? 80, height = request.height ?? 24;
  const fixtures = fixturePackages(request);
  let current = state.init(list([]), new execute.State(origin.https('eyg.test'), fixtures.initial));
  let world = sandbox.sandbox();
  for (const [path, text] of Object.entries(request.files || {})) world = sandbox.with_file(world, resolve('/', path), text);
  if (fixtures.packages.length) world = sandbox.with_network(world, (request, accumulator) => {
    const module = fixtures.packages.find(p => request.path.includes(p.cidText));
    return [new runtime.Ok(response.set_body(response.new$(module ? 200 : 404), module ? module.bytes : runtime.toBitArray([]))), accumulator];
  }, undefined);
  const frames = [frame(current, width, height)];
  for (const event of request.events || []) {
    if (event.resize) [width, height] = event.resize;
    else {
      const input = event.paste !== undefined ? new backend.Paste(event.paste)
        : event.tick ? backend.InputEvent$Tick$const : new backend.KeyPress(event.key);
      let result = state.update(current, new state.Input(input));
      current = result[0];
      const pending = array(result[1]);
      let budget = 1000;
      while (pending.length) {
        if (!budget--) throw new Error('oracle effect budget exhausted');
        const [outcome, nextWorld] = sandbox.run(pending.shift(), world);
        world = nextWorld;
        if (!(outcome instanceof sandbox.Returned)) throw new Error('oracle TUI exited');
        result = state.update(current, new state.Task(outcome[0]));
        current = result[0];
        pending.push(...array(result[1]));
      }
    }
    frames.push(frame(current, width, height));
  }
  return { frames };
}

export function benchmark(request) {
  const width = request.width ?? 80, height = request.height ?? 24;
  const samples_ns = [];
  for (let iteration = 0; iteration < (request.iterations ?? 100); ++iteration) {
    let current = state.init(list([]), new execute.State(origin.https('eyg.test'), cache.empty()));
    let world = sandbox.sandbox();
    frame(current, width, height);
    for (const event of request.events || []) {
      const started = performance.now();
      const input = event.paste !== undefined ? new backend.Paste(event.paste) : new backend.KeyPress(event.key);
      let result = state.update(current, new state.Input(input));
      current = result[0];
      const pending = array(result[1]);
      let budget = 1000;
      while (pending.length) {
        if (!budget--) throw new Error('oracle effect budget exhausted');
        const [outcome, nextWorld] = sandbox.run(pending.shift(), world);
        world = nextWorld;
        if (!(outcome instanceof sandbox.Returned)) throw new Error('oracle TUI exited');
        result = state.update(current, new state.Task(outcome[0]));
        current = result[0];
        pending.push(...array(result[1]));
      }
      frame(current, width, height);
      samples_ns.push(Math.round((performance.now() - started) * 1e6));
    }
  }
  return { samples_ns };
}

export function handle(request) {
  if (request.op === 'eval') return evaluate(request);
  if (request.op === 'pretty') return pretty(request);
  if (request.op === 'pretty_source' || request.op === 'source_parse') return prettySource(request);
  if (request.op === 'tui') return tui(request);
  if (request.op === 'bench_tui') return benchmark(request);
  if (request.op === 'package_metadata') return {packages: fixturePackages(request).packages.map(p => ({name:p.name,version:p.version,cid:p.cidText,program:p.program}))};
  if (request.op === 'hub_fixture') return httpHubFixture(request);
  if (request.op === 'input') {
    const parsed = input.parse(request.text);
    const events = [...array(parsed.events), ...request.flush ? array(input.flush(parsed.remainder)) : []];
    const mouseButton = (b) => cls(b) === 'MouseLeft' ? 'left' : cls(b) === 'MouseMiddle' ? 'middle' : 'right';
    return {events: events.map(e => {
      if (e instanceof backend.KeyPress) return {key:e.key};
      if (e instanceof backend.Paste) return {paste:e.text};
      if (e instanceof backend.MouseScroll) return {mouse:{kind:'scroll',x:e.x,y:e.y,up:e.up}};
      if (e instanceof backend.MouseMove) return {mouse:{kind:'move',x:e.x,y:e.y}};
      const kind = e instanceof backend.MousePress ? 'press' : e instanceof backend.MouseRelease ? 'release' : 'drag';
      return {mouse:{kind,x:e.x,y:e.y,button:mouseButton(e.button)}};
    }), remainder: request.flush ? '' : parsed.remainder};
  }
  if (request.op === 'parse') {
    const parsed = parser.block(token.drop_comments(token.drop_whitespace(lexer.lex(request.source))));
    if (cls(parsed) !== 'Ok') return { parse_error: true };
    return { program: JSON.parse(codec.to_string(parsed[0][0])) };
  }
  if (request.op === 'diagnostic') {
    const parsed = sourceParser.all_from_string(request.source);
    return {message: cls(parsed) === 'Ok' ? '' : sourceParser.format_error(parsed[0], request.source)};
  }
  throw new Error(`unknown op ${request.op}`);
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  for await (const line of createInterface({input: process.stdin, crlfDelay: Infinity})) {
    try {
      // Some upstream morph cases print diagnostic messages. Keep their real
      // side effects on stderr without corrupting this adapter's JSONL channel.
      const originalLog = console.log;
      let result;
      try {
        console.log = (...parts) => process.stderr.write(parts.map(String).join(' ') + '\n');
        result = handle(JSON.parse(line));
      } finally { console.log = originalLog; }
      process.stdout.write(JSON.stringify(result) + '\n');
    }
    catch (error) { process.stdout.write(JSON.stringify({adapter_error: String(error), stack: error.stack}) + '\n'); }
  }
}
