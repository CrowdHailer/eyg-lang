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
  case exp {
    e.Apply(e.Apply(e.Cons, value), tail) -> {
      let #(items, tail) = gather_items(tail, [value])
      render_list(list.reverse(items), render(tail))
    }
    e.Tail -> "[]"
    e.Apply(e.Apply(e.Extend(label), value), rest) -> {
      // Do string in render_fields
      let #(fields, tail) = gather_fields(rest, [#(label, value)])
      let fields =
        list.map(fields, fn(field) {
          string.concat([field.0, ": ", render(field.1)])
        })
        |> list.intersperse(", ")
        |> string.concat
      case tail {
        e.Empty -> string.concat(["{", fields, "}"])
        _ -> panic as "improper record"
      }
    }
    e.Apply(e.Apply(e.Overwrite(label), value), rest) -> {
      // Do string in render_fields
      let #(fields, tail) = gather_fields(rest, [#(label, value)])
      let fields =
        list.map(fields, fn(field) {
          string.concat([field.0, ": ", render(field.1)])
        })
        |> list.intersperse(", ")
        |> string.concat
      // Wrap in brackets because sometimes the thing is treated as a block
      string.concat(["({...", render(tail), ", ", fields, "})"])
    }
    e.Empty -> "{}"
    e.Apply(e.Select(label), from) -> string.concat([render(from), ".", label])
    e.Apply(e.Tag(label), value) ->
      string.concat(["{$T: \"", label, "\", v: ", render(value), "}"])
    // Not needed call works fine
    // e.Apply(e.Apply(e.Apply(e.Case(label), branch), otherwise), value) -> {
    //   let branches = render_branches(label, branch, otherwise, "")
    //   ["(function($) { switch ($.$T) {\n", branches, "}})(", render(value), ")"]
    //   |> string.concat()
    // }
    e.Apply(e.Apply(e.Case(label), branch), otherwise) -> {
      let branches = render_branches(label, branch, otherwise, "")
      ["(function($) { switch ($.$T) {\n", branches, "}})"]
      |> string.concat()
    }
    e.Apply(f, a) -> string.concat([render(f), "(", render(a), ")"])
    e.Variable(x) -> x
    e.Lambda(x, body) -> {
      string.concat(["((", x, ") => {\n", render_body(body), ";\n})"])
    }
    e.Let(x, value, then) -> {
      string.concat(["let ", x, " = ", render(value), ";\n", render(then)])
    }
    e.Integer(value) -> int.to_string(value)
    _ -> {
      io.debug(exp)
      panic
    }
  }
}

fn render_body(body) {
  case body {
    e.Let(x, v, t) ->
      string.concat(["  let ", x, " = ", render(v), ";\n", render_body(t)])
    other -> string.concat(["  return ", render(other)])
  }
}

fn render_list(items, acc) {
  case items {
    [] -> acc
    [i, ..rest] ->
      render_list(rest, string.concat(["[", render(i), ", ", acc, "]"]))
  }
}

fn gather_items(tail, acc) {
  case tail {
    e.Apply(e.Apply(e.Cons, value), tail) -> gather_items(tail, [value, ..acc])
    t -> #(list.reverse(acc), t)
  }
}

fn gather_fields(tail, acc) {
  case tail {
    e.Apply(e.Apply(e.Extend(label), value), tail) ->
      gather_fields(tail, [#(label, value), ..acc])
    t -> #(list.reverse(acc), t)
  }
}

fn render_branches(label, branch, otherwise, acc: String) {
  let acc =
    string.concat([acc, "case '", label, "': ", render_body(branch), "($.v)\n"])
  case otherwise {
    e.Apply(e.Apply(e.Case(label), branch), otherwise) ->
      render_branches(label, branch, otherwise, acc)
    e.NoCases -> acc
    _ -> string.concat([acc, "default: ", render_body(otherwise), "($)"])
  }
}
