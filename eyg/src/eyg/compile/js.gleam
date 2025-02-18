import eyg/ir/tree as ir
import gleam/int
import gleam/io
import gleam/list
import gleam/string

// can't wrap program in `()` because js assumes expression and breaks with let
// but also cant wrap in `{}` because in brackets is assuemd to be object
fn assign_to(source: ir.Node(Nil), label) {
  let #(exp, _meta) = source
  case exp {
    ir.Let(x, v, t) -> ir.let_(x, v, assign_to(t, label))
    _ -> ir.let_(label, source, ir.apply(ir.builtin("run"), ir.variable(label)))
  }
}

pub fn render(exp: ir.Node(Nil)) {
  let used = builtins_used(exp, [])

  let program = case list.contains(used, "bind") {
    False -> do_render(exp)
    // brackets to handle let statements, render with one extra indent
    True -> do_render(assign_to(exp, "program"))
  }
  [program, ..list.map(used, render_builtin)]
  |> list.reverse
  |> list.intersperse(";\n")
  |> string.concat
}

fn builtins_used(source, acc) {
  let #(exp, _meta) = source
  case exp {
    ir.Apply(func, arg) ->
      acc
      |> builtins_used(func, _)
      |> builtins_used(arg, _)
    ir.Let(_, value, then) ->
      acc
      |> builtins_used(value, _)
      |> builtins_used(then, _)
    ir.Lambda(_, body) ->
      acc
      |> builtins_used(body, _)
    ir.Handle(_label) -> ["handle", ..acc]
    ir.Builtin(i) ->
      case list.contains(acc, i) {
        True -> acc
        False -> [i, ..acc]
      }
    _ -> acc
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
    ir.Binary(_) -> "binary_not_supported"
    ir.String(content) -> string.concat(["\"", escape_html(content), "\""])
    ir.Perform(label) -> string.concat(["perform (\"", label, "\")"])
    ir.Handle(label) -> string.concat(["handle (\"", label, "\")"])
    ir.Builtin(identifier) -> identifier
    ir.Vacant -> "throw TODO"
    _ -> {
      io.debug(exp)
      panic as "unsupported compilation expression"
    }
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

let extrinsic = {
  Alert: (message) => window.alert(message), 
  Ask: (x) => 10, 
  Log: (x) => console.log(x) 
};
let run = (exec) => {
  let m = exec
  while (m instanceof Eff) {
    m = m.k(extrinsic[m.label](m.value));
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
    "int_subtract" -> "let int_subtract = (x) => (y) => x - y"
    "int_multiply" -> "let int_multiply = (x) => (y) => x * y"
    "int_divide" -> "let int_divide = (x) => (y) => Math.trunc(x / y)"
    "int_parse" ->
      "let int_parse = (x) => {
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
  if (y > x) return {$T: \"Gt\", $V: {}}
  return {$T: \"Eq\", $V: {}}
}"
    "string_append" -> "let string_append = (x) => (y) => x + y"
    "string_uppercase" -> "let string_uppercase = (x) => x.toUpperCase()"
    "string_lowercase" -> "let string_lowercase = (x) => x.toLowerCase()"
    "string_starts_with" ->
      "let string_starts_with = (x) => (y) => x.startsWith(y) ? {$T: \"Ok\", $V: x.slice(y.length)} : {$T: \"Error\", $V: {}}"
    "string_ends_with" ->
      "let string_ends_with = (x) => (y) => x.endsWith(y) ? {$T: \"Ok\", $V: x.slice(0, -y.length)} : {$T: \"Error\", $V: {}}"
    "string_length" -> "let string_length = (x) => x.length"
    "list_pop" ->
      "let list_pop = (items) =>
  items.length == 0
  ? {$T: \"Error\", $V: {}}
  : {$T: \"Ok\", $V: {head: items[0], tail: items[1]}}"
    "list_fold" ->
      "let list_fold = (items) => (acc) => (f) => {
  let item;
  while (items.length != 0) {
    item = items[0];
    items = items[1];
    acc = f(acc)(item);
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
