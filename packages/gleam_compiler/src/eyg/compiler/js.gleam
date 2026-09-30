import eyg/ir/tree as ir
import gleam/int
import gleam/list
import gleam/string

// can't wrap program in `()` because js assumes expression and breaks with let
// but also cant wrap in `{}` because in brackets is assuemd to be object
// label is the name of a function that is passed to the runner.
fn assign_to(source: ir.Node(Nil), label) {
  let #(exp, _meta) = source
  case exp {
    ir.Let(x, v, t) -> ir.let_(x, v, assign_to(t, label))
    _ -> ir.let_(label, source, ir.apply(ir.builtin("run"), ir.variable(label)))
  }
}

pub const basic = "(label, value) => ({Alert: (x) => window.alert(x), Ask: (_) => 10, Log: (x) => console.log(x)})[label](value)"

pub fn render(exp: ir.Node(Nil), handler: String) -> String {
  let used = ir.list_builtins(exp)
  let #(definitions, program) = case needs_effect_runtime(exp) {
    False -> #(list.map(used, render_builtin), do_render(exp))
    True -> {
      let used = [
        "bind",
        "handle",
        ..list.filter(used, fn(x) { x != "bind" && x != "handle" })
      ]
      #(
        ["let extrinsic = " <> handler, ..list.map(used, render_builtin)],
        do_render(assign_to(exp, "program")),
      )
    }
  }
  list.append(definitions, [program])
  |> list.filter(fn(x) { x != "" })
  |> list.intersperse(";\n")
  |> string.concat
}

fn needs_effect_runtime(node: ir.Node(Nil)) {
  case node.0 {
    ir.Perform(_)
    | ir.Handle(_)
    | ir.Builtin("bind")
    | ir.Builtin("fix")
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
    ir.Tail -> "[]"
    ir.Apply(#(ir.Apply(#(ir.Extend(label), _), value), _), rest) -> {
      // Do string in render_fields
      let #(fields, tail) = gather_extends(rest, [#(label, value)])
      let fields =
        list.map(fields, fn(field) {
          string.concat([field.0, ": ", do_render(field.1)])
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
          string.concat([field.0, ": ", do_render(field.1)])
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
    ir.String(content) -> string.concat(["\"", escape_html(content), "\""])
    ir.Perform(label) -> string.concat(["perform (\"", label, "\")"])
    ir.Handle(label) -> string.concat(["handle (\"", label, "\")"])
    ir.Builtin(identifier) -> identifier
    ir.Vacant -> "throw TODO"
    _ -> {
      panic as "unsupported compilation expression"
    }
  }
}

fn render_bytes(bytes) {
  case bytes {
    <<byte:8, rest:bits>> -> int.to_string(byte) <> "," <> render_bytes(rest)
    _ -> ""
  }
}

fn escape_html(content) {
  content
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
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
    "bind" ->
      "function Eff(label, value, k) {
  this.label = label;
  this.value = value;
  this.k = k;
}

let bind = (m, then) => {
  if (!(m instanceof Eff)) return then(m);
  let k = (x) => bind(m.k(x), then);
  return new Eff(m.label, m.value, k);
};

let perform = (label) => (value) => new Eff(label, value, (x) => x);

let run = (exec) => {
  let m = exec
  while (m instanceof Eff) {
    m = m.k(extrinsic(m.label, m.value));
  }
  return m;
}"
    "handle" ->
      "let handle = (label) => (handler) => (exec) => {
  return do_handle(label, handler, exec({}));
};

let do_handle = (label, handler, m) => {
  if (!(m instanceof Eff)) return m;
  let k = (x) => do_handle(label, handler, m.k(x));
  if (m.label == label) return handler(m.value)(k);
  return new Eff(m.label, m.value, k);
}"
    "int_add" -> "let int_add = (x) => (y) => x + y"
    "int_absolute" -> "let int_absolute = (x) => Math.abs(x)"
    "fix" ->
      "let fix = (f) => {
  const self = (x) => bind(f(self), (g) => g(x));
  return f(self);
}"
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
    "binary_fold" ->
      "let binary_fold = (bytes) => (acc) => (f) => {
  const loop = (start, acc) => {
    for (let i = start; i < bytes.length; i++) {
      const previous = acc;
      acc = bind(f(bytes[i]), (g) => g(previous));
      if (acc instanceof Eff) return bind(acc, (value) => loop(i + 1, value));
    }
    return acc;
  };
  return loop(0, acc);
}"
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
    "list_fold" ->
      "let list_fold = (items) => (acc) => (f) => {
  while (items.length != 0) {
    const item = items[0];
    items = items[1];
    const previous = acc;
    acc = bind(f(item), (g) => g(previous));
    if (acc instanceof Eff) {
      const rest = items;
      return bind(acc, (value) => list_fold(rest)(value)(f));
    }
  }
  return acc
}"
    _ ->
      string.concat([
        "let ",
        identifier,
        " = (_) => { throw \"",
        identifier,
        "\" }",
      ])
  }
}
