// in lang2 PR
// type not used
// scope is about unique variables fixed with ir
// in tail is still relevant
// don't need to wrap expression with a
// BUT still might
import gleam/io
import gleam/int
import gleam/list
import gleam/string
import eygir/expression as e

pub fn render(exp) {
  let used = builtins_used(exp, [])

  [do_render(exp), ..list.map(used, render_builtin)]
  |> list.reverse
  |> list.intersperse(";\n")
  |> string.concat
}

fn builtins_used(exp, acc) {
  case exp {
    e.Apply(func, arg) ->
      acc
      |> builtins_used(func, _)
      |> builtins_used(arg, _)
    e.Let(_, value, then) ->
      acc
      |> builtins_used(value, _)
      |> builtins_used(then, _)
    e.Lambda(_, body) ->
      acc
      |> builtins_used(body, _)
    e.Builtin(i) ->
      case list.contains(acc, i) {
        True -> acc
        False -> [i, ..acc]
      }
    _ -> acc
  }
}

fn do_render(exp) {
  case exp {
    e.Apply(e.Apply(e.Cons, value), tail) -> {
      let #(items, tail) = gather_items(tail, [value])
      render_list(list.reverse(items), do_render(tail))
    }
    e.Tail -> "[]"
    e.Apply(e.Apply(e.Extend(label), value), rest) -> {
      // Do string in render_fields
      let #(fields, tail) = gather_extends(rest, [#(label, value)])
      let fields =
        list.map(fields, fn(field) {
          string.concat([field.0, ": ", do_render(field.1)])
        })
        |> list.intersperse(", ")
        |> string.concat
      case tail {
        // Wrap in brackets because sometimes the thing is treated as a block
        e.Empty -> string.concat(["({", fields, "})"])
        _ -> panic as "improper record"
      }
    }
    e.Apply(e.Apply(e.Overwrite(label), value), rest) -> {
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
    e.Empty -> "({})"
    e.Apply(e.Select(label), from) ->
      string.concat([do_render(from), ".", label])
    e.Apply(e.Tag(label), value) ->
      string.concat(["{$T: \"", label, "\", $V: ", do_render(value), "}"])
    // Not needed call works fine
    // e.Apply(e.Apply(e.Apply(e.Case(label), branch), otherwise), value) -> {
    //   let branches = render_branches(label, branch, otherwise, "")
    //   ["(function($) { switch ($.$T) {\n", branches, "}})(", do_render(value), ")"]
    //   |> string.concat()
    // }
    e.Apply(e.Apply(e.Case(label), branch), otherwise) -> {
      let branches = render_branches(label, branch, otherwise, "")
      ["(function($) { switch ($.$T) {\n", branches, "}})"]
      |> string.concat()
    }
    e.Apply(f, a) -> string.concat([do_render(f), "(", do_render(a), ")"])
    e.Variable(x) -> x
    e.Lambda(x, body) -> {
      string.concat(["((", x, ") => {\n", render_body(body), ";\n})"])
    }
    e.Let(x, value, then) -> {
      string.concat(["let ", x, " = ", do_render(value), ";\n", do_render(then)])
    }
    e.Integer(value) -> int.to_string(value)
    e.Binary(_) -> "binary_not_supported"
    e.Str(content) -> string.concat(["\"", escape_html(content), "\""])
    e.Builtin(identifier) -> identifier
  }
  // _ -> {
  //   io.debug(exp)
  //   panic
  // }
}

fn escape_html(content) {
  content
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("&", "&amp;")
  |> string.replace("<", "&lt;")
  |> string.replace(">", "&gt;")
}

fn render_body(body) {
  case body {
    e.Let(x, v, t) ->
      string.concat(["  let ", x, " = ", do_render(v), ";\n", render_body(t)])
    other -> string.concat(["  return ", do_render(other)])
  }
}

fn render_list(items, acc) {
  case items {
    [] -> acc
    [i, ..rest] ->
      render_list(rest, string.concat(["[", do_render(i), ", ", acc, "]"]))
  }
}

fn gather_items(tail, acc) {
  case tail {
    e.Apply(e.Apply(e.Cons, value), tail) -> gather_items(tail, [value, ..acc])
    t -> #(list.reverse(acc), t)
  }
}

fn gather_extends(tail, acc) {
  case tail {
    e.Apply(e.Apply(e.Extend(label), value), tail) ->
      gather_extends(tail, [#(label, value), ..acc])
    t -> #(list.reverse(acc), t)
  }
}

fn gather_overwrites(tail, acc) {
  case tail {
    e.Apply(e.Apply(e.Overwrite(label), value), tail) ->
      gather_overwrites(tail, [#(label, value), ..acc])
    t -> #(list.reverse(acc), t)
  }
}

fn render_branches(label, branch, otherwise, acc: String) {
  let acc =
    string.concat([acc, "case '", label, "': ", render_body(branch), "($.$V)\n"])
  case otherwise {
    e.Apply(e.Apply(e.Case(label), branch), otherwise) ->
      render_branches(label, branch, otherwise, acc)
    e.NoCases -> acc
    _ -> string.concat([acc, "default: ", render_body(otherwise), "($)"])
  }
}

fn render_builtin(identifier) {
  case identifier {
    "integer_add" -> "let integer_add = (x) => (y) => x + y"
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
