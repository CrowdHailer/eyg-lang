// in lang2 PR
// type not used
// scope is about unique variables fixed with ir
// in tail is still relevant
// don't need to wrap expression with a
// BUT still might
import eygir/annotated as a
import gleam/int
import gleam/io
import gleam/list
import gleam/string

// can't wrap program in `()` because js assumes expression and breaks with let
// but also cant wrap in `{}` because in brackets is assuemd to be object
fn assign_to(source: a.Node(Nil), label) {
  let #(exp, _meta) = source
  case exp {
    a.Let(x, v, t) -> a.let_(x, v, assign_to(t, label))
    _ -> a.let_(label, source, a.apply(a.builtin("run"), a.variable(label)))
  }
}

pub fn render(exp: a.Node(Nil)) {
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
    a.Apply(func, arg) ->
      acc
      |> builtins_used(func, _)
      |> builtins_used(arg, _)
    a.Let(_, value, then) ->
      acc
      |> builtins_used(value, _)
      |> builtins_used(then, _)
    a.Lambda(_, body) ->
      acc
      |> builtins_used(body, _)
    a.Handle(_label) -> ["handle", ..acc]
    a.Builtin(i) ->
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
    a.Apply(#(a.Apply(#(a.Cons, _), value), _), tail) -> {
      let #(items, tail) = gather_items(tail, [value])
      render_list(list.reverse(items), do_render(tail))
    }
    a.Tail -> "[]"
    a.Apply(#(a.Apply(#(a.Extend(label), _), value), _), rest) -> {
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
        a.Empty -> string.concat(["({", fields, "})"])
        _ -> panic as "improper record"
      }
    }
    a.Apply(#(a.Apply(#(a.Overwrite(label), _), value), _), rest) -> {
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
    a.Empty -> "({})"
    a.Apply(#(a.Select(label), _), from) ->
      string.concat([do_render(from), ".", label])
    a.Apply(#(a.Tag(label), _), value) ->
      string.concat(["{$T: \"", label, "\", $V: ", do_render(value), "}"])
    // Not needed call works fine
    // e.Apply(e.Apply(e.Apply(e.Case(label), branch), otherwise), value) -> {
    //   let branches = render_branches(label, branch, otherwise, "")
    //   ["(function($) { switch ($.$T) {\n", branches, "}})(", do_render(value), ")"]
    //   |> string.concat()
    // }
    a.Apply(#(a.Apply(#(a.Case(label), _), branch), _), otherwise) -> {
      let branches = render_branches(label, branch, otherwise, "")
      ["(function($) { switch ($.$T) {\n", branches, "}})"]
      |> string.concat()
    }
    a.Apply(#(a.Apply(#(a.Builtin("bind"), _), value), _), then) ->
      string.concat(["bind(", do_render(value), ", ", do_render(then), ")"])
    a.Apply(f, a) -> string.concat([do_render(f), "(", do_render(a), ")"])
    a.Variable(x) -> x
    a.Lambda(x, body) -> {
      string.concat(["((", x, ") => {\n", render_body(body), ";\n})"])
    }
    a.Let(x, value, then) -> {
      string.concat(["let ", x, " = ", do_render(value), ";\n", do_render(then)])
    }
    a.Integer(value) -> int.to_string(value)
    a.Binary(_) -> "binary_not_supported"
    a.Str(content) -> string.concat(["\"", escape_html(content), "\""])
    a.Perform(label) -> string.concat(["perform (\"", label, "\")"])
    a.Handle(label) -> string.concat(["handle (\"", label, "\")"])
    a.Builtin(identifier) -> identifier
    a.Vacant -> "throw TODO"
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
    a.Let(x, v, t) ->
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
    a.Apply(#(a.Apply(#(a.Cons, _), value), _), tail) ->
      gather_items(tail, [value, ..acc])
    _ -> #(list.reverse(acc), source)
  }
}

fn gather_extends(source, acc) {
  let #(tail, _) = source
  case tail {
    a.Apply(#(a.Apply(#(a.Extend(label), _), value), _), tail) ->
      gather_extends(tail, [#(label, value), ..acc])
    _ -> #(list.reverse(acc), source)
  }
}

fn gather_overwrites(source, acc) {
  let #(tail, _) = source

  case tail {
    a.Apply(#(a.Apply(#(a.Overwrite(label), _), value), _), tail) ->
      gather_overwrites(tail, [#(label, value), ..acc])
    _ -> #(list.reverse(acc), source)
  }
}

fn render_branches(label, branch, otherwise, acc: String) {
  let acc =
    string.concat([acc, "case '", label, "': ", render_body(branch), "($.$V)\n"])
  let #(exp, _meta) = otherwise
  case exp {
    a.Apply(#(a.Apply(#(a.Case(label), _), branch), _), otherwise) ->
      render_branches(label, branch, otherwise, acc)
    a.NoCases -> acc
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
    "int_absolute" -> "let int_absolute = (x) => Math.abs(x)"
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
