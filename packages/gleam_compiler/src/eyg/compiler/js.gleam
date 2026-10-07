import eyg/compiler/runtime
import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/string

pub const basic =
  "(label, value) => ({Alert: (x) => window.alert(x), Ask: (_) => 10, Log: (x) => console.log(x)})[label](value)"

pub fn render(exp: ir.Node(Nil), handler: String) -> String {
  render_with(exp, handler, do_render, "")
}

pub fn render_expression(exp: ir.Node(Nil), handler: String) -> String {
  "(() => {\n" <> render_with(exp, handler, render_body, "return ") <> ";\n})()"
}

fn render_with(
  exp: ir.Node(Nil),
  handler: String,
  render_program,
  prefix,
) -> String {
  let used = ir.list_builtins(exp)
  let used = case needs_query_runtime(exp) {
    True -> ["$query", ..used]
    False -> used
  }
  let #(definitions, program) = case needs_effect_runtime(exp) {
    False -> #(list.map(used, render_builtin), render_program(exp))
    True -> #(
      [
        "const extrinsic = " <> handler,
        "const $runtime = (" <> runtime.source <> ").create(extrinsic)",
        ..runtime_bindings(used)
      ],
      prefix <> "$run(" <> stack_expression(exp) <> ")",
    )
  }
  list.append(definitions, [program])
  |> list.filter(fn(x) { x != "" })
  |> list.intersperse(";\n")
  |> string.concat
}

/// ES module whose host operations remain suspended until run or runAsync.
pub fn render_module(exp: ir.Node(Nil)) -> String {
  [
    "const $library = (" <> runtime.source <> ")",
    "const $runtime = $library.create_deferred()",
    ..list.append(runtime_bindings(query_builtins(exp)), [
      "const program = $run(" <> stack_expression(exp) <> ")",
      "export default {program, run: $library.run_effects, runAsync: $library.run_effects_async, Eff: $library.Eff}",
    ])
  ]
  |> string.join(";\n")
  |> string.append(";\n")
}

fn query_builtins(exp) {
  let used = ir.list_builtins(exp)
  case needs_query_runtime(exp) {
    True -> ["equal", "$query", ..list.filter(used, fn(x) { x != "equal" })]
    False -> used
  }
}

fn runtime_bindings(used) {
  [
    "const $run = $runtime.run, $fn = $runtime.function_, $call = $runtime.call, $bind = $runtime.bind, $handle = $runtime.handle, $perform = $runtime.perform, $mask = $runtime.mask, $shallow = $runtime.shallow",
    "const bind = $runtime.bind_builtin, fix = $runtime.fix, list_fold = $runtime.list_fold, binary_fold = $runtime.binary_fold, never = $runtime.never, pure = $runtime.pure_",
    ..used
    |> list.filter(fn(name) { !runtime.defines(name) })
    |> list.map(render_builtin)
  ]
}

// Lower every application in a runtime-backed program, not only effectful
// calls: pure tail recursion and calls to returned state functions need the
// same trampoline. Straight-line pure programs keep the compact renderer.
fn stack_expression(source: ir.Node(Nil)) -> String {
  case source.0 {
    ir.Apply(f, a) ->
      "$bind("
      <> stack_expression(f)
      <> ", $f => $bind("
      <> stack_expression(a)
      <> ", $a => $call($f, $a)))"
    ir.Let(x, value, then) ->
      "$bind("
      <> stack_expression(value)
      <> ", "
      <> x
      <> " => "
      <> stack_expression(then)
      <> ")"
    ir.Lambda(x, body) -> "$fn(" <> x <> " => " <> stack_expression(body) <> ")"
    ir.Variable(x) -> x
    ir.Integer(_) | ir.String(_) | ir.Binary(_) | ir.Empty | ir.Tail ->
      do_render(source)
    ir.Cons -> "$fn(x => xs => [x, xs])"
    ir.Extend(label) | ir.Overwrite(label) ->
      "$fn(value => record => ({...record, [\""
      <> escape_js(label)
      <> "\"]: value}))"
    ir.Select(label) -> "$fn(record => record[\"" <> escape_js(label) <> "\"])"
    ir.Tag(label) ->
      "$fn(value => ({$T: \"" <> escape_js(label) <> "\", $V: value}))"
    ir.Case(label) ->
      "$fn(branch => otherwise => value => value.$T === \""
      <> escape_js(label)
      <> "\" ? $call(branch, value.$V) : $call(otherwise, value))"
    ir.NoCases -> "$fn(value => { throw {eygBreak: {NoMatch: value}}; })"
    ir.Perform(label) ->
      "$fn(value => $perform(\"" <> escape_js(label) <> "\", value))"
    ir.Handle(label) ->
      "$fn(handler => body => $handle(\""
      <> escape_js(label)
      <> "\", handler, body))"
    ir.Mask(label) -> "$fn(body => $mask(\"" <> escape_js(label) <> "\", body))"
    ir.Shallow(label) ->
      "$fn(handler => onReturn => body => $shallow(\""
      <> escape_js(label)
      <> "\", handler, onReturn, body))"
    ir.Query(ir.EmptyTable) -> do_render(source)
    ir.Query(_) -> "$fn(" <> do_render(source) <> ")"
    ir.Builtin(name) ->
      case runtime.defines(name) || render_builtin(name) != "" {
        True -> "$fn(" <> name <> ")"
        False -> render_break("UndefinedBuiltin", name)
      }
    ir.Vacant -> render_break("NotImplemented", "")
    ir.Reference(_) -> panic as "unsupported compilation reference"
  }
}

fn needs_query_runtime(node: ir.Node(a)) {
  case node.0 {
    ir.Query(_) -> True
    _ -> list.any(ir.children(node), needs_query_runtime)
  }
}

pub fn needs_effect_runtime(node: ir.Node(a)) {
  case node.0 {
    ir.Query(_)
    | ir.Perform(_)
    | ir.Handle(_)
    | ir.Shallow(_)
    | ir.Mask(_)
    | ir.Builtin("pure")
    | ir.Builtin("bind")
    | ir.Builtin("fix")
    | ir.Builtin("never")
    | ir.Builtin("list_fold")
    | ir.Builtin("binary_fold") -> True
    _ -> list.any(ir.children(node), needs_effect_runtime)
  }
}

fn do_render(source) {
  let #(exp, _meta) = source
  case exp {
    ir.Apply(#(ir.Apply(#(ir.Cons, _), value), _), tail) -> {
      let #(items, tail) = gather_items(tail, [value])
      render_list(list.reverse(items), do_render(tail))
    }
    ir.Query(operation) ->
      case operation {
        ir.EmptyTable -> "$query.empty()"
        ir.Fact(label) -> "$query.fact(\"" <> escape_js(label) <> "\")"
        ir.Rule -> "$query.rule"
        ir.Merge -> "$query.merge"
        ir.Resolve(label) -> "$query.resolve(\"" <> escape_js(label) <> "\")"
        ir.Match(label, keys) ->
          "$query.match(\""
          <> escape_js(label)
          <> "\", ["
          <> string.join(
            list.map(keys, fn(k) { "\"" <> escape_js(k) <> "\"" }),
            ", ",
          )
          <> "])"
      }
    ir.Tail -> "[]"
    ir.Apply(#(ir.Apply(#(ir.Extend(label), _), value), _), rest) -> {
      // Do string in render_fields
      let #(fields, tail) = gather_extends(rest, [#(label, value)])
      let fields =
        list.map(fields, fn(field) {
          string.concat([record_key(field.0), ": ", do_render(field.1)])
        })
        |> list.intersperse(", ")
        |> string.concat
      case tail.0 {
        // Wrap in brackets because sometimes the thing is treated as a block
        ir.Empty -> string.concat(["({", fields, "})"])
        _ -> panic as "improper record"
      }
    }
    ir.Apply(#(ir.Apply(#(ir.Overwrite(label), _), value), _), rest) -> {
      // Do string in render_fields
      let #(fields, tail) = gather_overwrites(rest, [#(label, value)])
      let fields =
        list.map(fields, fn(field) {
          string.concat([record_key(field.0), ": ", do_render(field.1)])
        })
        |> list.intersperse(", ")
        |> string.concat
      // Wrap in brackets because sometimes the thing is treated as a block
      string.concat(["({...", do_render(tail), ", ", fields, "})"])
    }
    ir.Empty -> "({})"
    ir.Apply(#(ir.Select(label), _), from) ->
      string.concat([do_render(from), ".", label])
    ir.Apply(#(ir.Tag(label), _), value) ->
      string.concat(["{$T: \"", label, "\", $V: ", do_render(value), "}"])
    // Not needed call works fine
    // e.Apply(e.Apply(e.Apply(e.Case(label), branch), otherwise), value) -> {
    //   let branches = render_branches(label, branch, otherwise, "")
    //   ["(function($) { switch ($.$T) {\n", branches, "}})(", do_render(value), ")"]
    //   |> string.concat()
    // }
    ir.Apply(#(ir.Apply(#(ir.Case(label), _), branch), _), otherwise) -> {
      let branches = render_branches(label, branch, otherwise, "")
      ["(function($) { switch ($.$T) {\n", branches, "}})"]
      |> string.concat()
    }
    ir.Apply(#(ir.Apply(#(ir.Builtin("bind"), _), value), _), then) ->
      string.concat(["bind(", do_render(value), ", ", do_render(then), ")"])
    ir.Apply(f, a) -> string.concat([do_render(f), "(", do_render(a), ")"])
    ir.Variable(x) -> x
    ir.Lambda(x, body) -> {
      string.concat(["((", x, ") => {\n", render_body(body), ";\n})"])
    }
    ir.Let(x, value, then) -> {
      string.concat(["let ", x, " = ", do_render(value), ";\n", do_render(then)])
    }
    ir.Integer(value) -> int.to_string(value)
    ir.Binary(bytes) -> "new Uint8Array([" <> render_bytes(bytes) <> "])"
    ir.String(content) -> string.concat(["\"", escape_js(content), "\""])
    ir.Perform(label) -> string.concat(["perform (\"", label, "\")"])
    ir.Handle(label) -> string.concat(["handle (\"", label, "\")"])
    ir.Builtin(identifier) ->
      case render_builtin(identifier) {
        "" -> render_break("UndefinedBuiltin", identifier)
        _ -> identifier
      }
    ir.Vacant -> render_break("NotImplemented", "")
    _ -> {
      panic as "unsupported compilation expression"
    }
  }
}

fn record_key(label) {
  case label {
    // Object literal syntax otherwise sets the prototype instead of a field.
    "__proto__" -> "[\"__proto__\"]"
    _ -> label
  }
}

fn render_break(kind, label) {
  "(() => { throw {eygBreak: {"
  <> kind
  <> ": \""
  <> escape_js(label)
  <> "\"}}; })()"
}

fn render_bytes(bytes) {
  case bytes {
    <<byte:8, rest:bits>> -> int.to_string(byte) <> "," <> render_bytes(rest)
    _ -> ""
  }
}

fn escape_js(content) {
  content
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
  |> string.replace("\u{2028}", "\\u2028")
  |> string.replace("\u{2029}", "\\u2029")
}

fn render_body(source) {
  let #(body, _) = source
  case body {
    ir.Let(x, v, t) ->
      string.concat(["  let ", x, " = ", do_render(v), ";\n", render_body(t)])
    _other -> string.concat(["  return ", do_render(source)])
  }
}

fn render_list(items, acc) {
  case items {
    [] -> acc
    [i, ..rest] ->
      render_list(rest, string.concat(["[", do_render(i), ", ", acc, "]"]))
  }
}

fn gather_items(source, acc) {
  let #(tail, _) = source
  case tail {
    ir.Apply(#(ir.Apply(#(ir.Cons, _), value), _), tail) ->
      gather_items(tail, [value, ..acc])
    _ -> #(list.reverse(acc), source)
  }
}

fn gather_extends(source, acc) {
  let #(tail, _) = source
  case tail {
    ir.Apply(#(ir.Apply(#(ir.Extend(label), _), value), _), tail) ->
      gather_extends(tail, [#(label, value), ..acc])
    _ -> #(list.reverse(acc), source)
  }
}

fn gather_overwrites(source, acc) {
  let #(tail, _) = source

  case tail {
    ir.Apply(#(ir.Apply(#(ir.Overwrite(label), _), value), _), tail) ->
      gather_overwrites(tail, [#(label, value), ..acc])
    _ -> #(list.reverse(acc), source)
  }
}

fn render_branches(label, branch, otherwise, acc: String) {
  let acc =
    string.concat([acc, "case '", label, "': ", render_body(branch), "($.$V)\n"])
  let #(exp, _meta) = otherwise
  case exp {
    ir.Apply(#(ir.Apply(#(ir.Case(label), _), branch), _), otherwise) ->
      render_branches(label, branch, otherwise, acc)
    ir.NoCases -> acc
    _ -> string.concat([acc, "default: ", render_body(otherwise), "($)"])
  }
}

fn render_builtin(identifier) {
  case identifier {
    "$query" ->
      "const $query = (() => {
  // Relations are Maps from a canonical key to the row, so membership is a
  // lookup and iteration keeps insertion order. Tables are never mutated after
  // construction, which makes it safe to cache indexes on a snapshot.
  class Table {
    constructor(facts = new Map(), rules = []) { this.facts = facts; this.rules = rules; }
  }
  const check = value => {
    if (!(value instanceof Table)) throw {eygBreak: {IncorrectTerm: 'Table'}};
    return value;
  };
  const pure = value => {
    if (typeof Eff !== 'undefined' && value instanceof Eff) throw {eygBreak: {ImpureQuery: value.label}};
    return check(value);
  };
  const ids = new WeakMap();
  let nextId = 0;
  const keyOf = value => {
    if (typeof value === 'number') return 'i' + value;
    if (typeof value === 'string') return 's' + JSON.stringify(value);
    if (typeof value === 'function') {
      if (!ids.has(value)) ids.set(value, nextId++);
      return 'f' + ids.get(value);
    }
    if (value instanceof Uint8Array) return 'b' + Array.from(value).join(',');
    if (Array.isArray(value)) {
      const items = [];
      while (value.length) { items.push(keyOf(value[0])); value = value[1]; }
      return 'l[' + items.join(',') + ']';
    }
    if (Object.hasOwn(value, '$T')) return 't' + value.$T + '(' + keyOf(value.$V) + ')';
    return 'r{' + Object.keys(value).sort().map(k => JSON.stringify(k) + ':' + keyOf(value[k])).join(',') + '}';
  };
  // Mutates `into`; only called on Maps owned by the caller.
  const absorb = (into, facts, grown) => {
    for (const [label, rows] of facts) {
      let relation = into.get(label);
      if (!relation) { relation = new Map(); into.set(label, relation); }
      for (const [key, row] of rows) {
        if (!relation.has(key)) { relation.set(key, row); if (grown) grown.add(label); }
      }
    }
    return into;
  };
  const copy = facts => new Map([...facts].map(([label, rows]) => [label, new Map(rows)]));
  const rows = (facts, label) => [...(facts.get(label) || new Map()).values()];
  const index = (db, label, keys) => {
    db.indexes ||= new Map();
    const name = label + '|' + keys.join(',');
    let found = db.indexes.get(name);
    if (!found) {
      found = new Map();
      for (const row of rows(db.facts, label)) {
        if (keys.length && (typeof row !== 'object' || keys.some(k => !Object.hasOwn(row, k)))) continue;
        const key = keyOf(Object.fromEntries(keys.map(k => [k, row[k]])));
        if (!found.has(key)) found.set(key, []);
        found.get(key).push(row);
      }
      db.indexes.set(name, found);
    }
    return found;
  };
  return {
    empty: () => new Table(),
    fact: label => row => new Table(new Map([[label, new Map([[keyOf(row), row]])]])),
    rule: rule => new Table(new Map(), [rule]),
    merge: a => b => new Table(absorb(copy(check(a).facts), check(b).facts), [...a.rules, ...b.rules]),
    match: (label, keys) => db => key => then => {
      check(db);
      db.reading?.add(label);
      const acc = new Map();
      for (const row of index(db, label, keys).get(keyOf(key)) || []) {
        let derived;
        try { derived = pure($runtime.run($runtime.call($runtime.pure_(then), row))); }
        catch (error) {
          if (error.eygBreak?.ImpureEffect !== undefined) throw {eygBreak: {ImpureQuery: error.eygBreak.ImpureEffect}};
          throw error;
        }
        if (derived.rules.length) throw {eygBreak: {IncorrectTerm: 'facts returned by a rule'}};
        absorb(acc, derived.facts);
      }
      return new Table(acc);
    },
    resolve: label => table => {
      check(table);
      const facts = copy(table.facts);
      const reads = new Map();
      let pending = table.rules.map((rule, i) => [i, rule]);
      while (pending.length) {
        const snapshot = new Table(copy(facts));
        const grown = new Set();
        for (const [i, rule] of pending) {
          snapshot.reading = new Set();
          let derived;
          try { derived = $runtime.run($runtime.call($runtime.pure_(rule), snapshot)); }
          catch (error) {
            if (error.eygBreak?.ImpureEffect !== undefined) throw {eygBreak: {ImpureQuery: error.eygBreak.ImpureEffect}};
            throw error;
          }
          pure(derived);

          if (derived.rules.length) throw {eygBreak: {IncorrectTerm: 'facts returned by a rule'}};
          reads.set(i, snapshot.reading);
          absorb(facts, derived.facts, grown);
        }
        delete snapshot.reading;
        pending = table.rules.map((rule, i) => [i, rule]).filter(([i]) => [...reads.get(i)].some(l => grown.has(l)));
      }
      table.reading?.add(label);
      return rows(facts, label).reduceRight((tail, head) => [head, tail], []);
    }
  };
})()"
    "int_add" -> "let int_add = (x) => (y) => x + y"
    "int_absolute" -> "let int_absolute = (x) => Math.abs(x)"
    "equal" ->
      "let equal = (x) => (y) => {
  const same = (a, b) => {
    if (a === b) return true;
    // EYG values do not use null, but host callbacks can return it. Since typeof null is 'object', guard it before Object.keys.
    if (a === null || b === null || typeof a !== 'object' || typeof b !== 'object') return false;
    if (Array.isArray(a) !== Array.isArray(b) || ArrayBuffer.isView(a) !== ArrayBuffer.isView(b)) return false;
    const keys = Object.keys(a);
    return keys.length === Object.keys(b).length && keys.every(k => Object.hasOwn(b, k) && same(a[k], b[k]));
  };
  return {$T: same(x, y) ? 'True' : 'False', $V: {}};
}"
    "$undefined_variable" ->
      "let $undefined_variable = (name) => { throw {eygBreak: {UndefinedVariable: name}}; }"
    "int_subtract" -> "let int_subtract = (x) => (y) => x - y"
    "int_multiply" -> "let int_multiply = (x) => (y) => x * y"
    "int_divide" ->
      "let int_divide = (x) => (y) => y === 0 ? {$T: \"Error\", $V: {}} : {$T: \"Ok\", $V: Math.trunc(x / y)}"
    "int_parse" ->
      "let int_parse = (x) => {
  if (!/^[-+]?(\\d+)$/.test(x)) return {$T: \"Error\", $V: {}};
  const parsed = Number.parseInt(x, 10);
  if (Number.isNaN(parsed)) {
    return {$T: \"Error\", $V: {}};
  }
  return {$T: \"Ok\", $V: parsed}
}"
    "int_to_string" -> "let int_to_string = (x) => x.toString()"
    "int_compare" ->
      "let int_compare = (x) => (y) => {
  if (x < y) return {$T: \"Lt\", $V: {}}
  if (x > y) return {$T: \"Gt\", $V: {}}
  return {$T: \"Eq\", $V: {}}
}"
    "string_append" -> "let string_append = (x) => (y) => x + y"
    "string_split" ->
      "let string_split = (x) => (separator) => {
  const parts = separator === '' ? Array.from(new Intl.Segmenter().segment(x), s => s.segment) : x.split(separator);
  return {head: parts[0] ?? '', tail: parts.slice(1).reduceRight((tail, head) => [head, tail], [])};
}"
    "string_uppercase" -> "let string_uppercase = (x) => x.toUpperCase()"
    "string_split_once" ->
      "let string_split_once = (x) => (separator) => {
  const i = x.indexOf(separator);
  return i < 0 ? {$T: 'Error', $V: {}} : {$T: 'Ok', $V: {pre: x.slice(0, i), post: x.slice(i + separator.length)}};
}"
    "string_lowercase" -> "let string_lowercase = (x) => x.toLowerCase()"
    "string_replace" ->
      "let string_replace = (x) => (pattern) => (replacement) => x.replaceAll(pattern, () => replacement)"
    "string_starts_with" ->
      "let string_starts_with = (x) => (y) => ({$T: x.startsWith(y) ? \"True\" : \"False\", $V: {}})"
    "string_ends_with" ->
      "let string_ends_with = (x) => (y) => ({$T: x.endsWith(y) ? \"True\" : \"False\", $V: {}})"
    "string_length" ->
      "let string_length = (x) => Array.from(new Intl.Segmenter().segment(x)).length"
    "list_pop" ->
      "let list_pop = (items) =>
  items.length == 0
  ? {$T: \"Error\", $V: {}}
  : {$T: \"Ok\", $V: {head: items[0], tail: items[1]}}"
    "string_to_binary" ->
      "let string_to_binary = (x) => new TextEncoder().encode(x)"
    "string_from_binary" ->
      "let string_from_binary = (x) => {
  try { return {$T: 'Ok', $V: new TextDecoder('utf-8', {fatal: true, ignoreBOM: true}).decode(x)}; }
  catch (_) { return {$T: 'Error', $V: {}}; }
}"
    "binary_from_integers" ->
      "let binary_from_integers = (items) => {
  const bytes = [];
  while (items.length) { bytes.push(items[0]); items = items[1]; }
  return new Uint8Array(bytes);
}"
    "binary_size" -> "let binary_size = (x) => x.length"
    "binary_concat" ->
      "let binary_concat = (x) => (y) => {
  const result = new Uint8Array(x.length + y.length);
  result.set(x); result.set(y, x.length);
  return result;
}"
    "binary_compare" ->
      "let binary_compare = (x) => (y) => {
  let order = x.length - y.length;
  for (let i = 0; i < Math.min(x.length, y.length); i++) {
    if (x[i] !== y[i]) { order = x[i] - y[i]; break; }
  }
  return {$T: order < 0 ? 'Lt' : order > 0 ? 'Gt' : 'Eq', $V: {}};
}"
    _ -> ""
  }
}
