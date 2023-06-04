import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e
import eyg/analysis/jm/tree
import eyg/analysis/jm/type_ as t
// reuse aterlier type
import atelier/view/type_

pub type Style {
  Default
  Keyword
  Missing
  Hole
  Integer
  String
  Union
  Effect
  Builtin
}

pub type Rendered =
  #(String, List(Int), Int, Style)

type Situ {
  Situ(path: List(Int))
}

pub fn print(source, analysis: tree.State) {
  let #(acc, info) = do_print(source, Situ([]), "\n", [], map.new(), analysis)
  #(list.reverse(acc), info)
}

fn do_print(source, situ, br, acc, info, analysis) {
  let Situ(path) = situ
  case source {
    e.Lambda(param, body) -> {
      let #(acc, info) =
        print_with_offset(param, path, Default, acc, info, analysis)
      let acc = print_keyword(" -> ", path, acc)
      print_block(body, Situ(list.append(path, [0])), br, acc, info, analysis)
    }
    e.Apply(e.Select(label), from) -> {
      let #(acc, info) =
        print_block(from, Situ(list.append(path, [1])), br, acc, info, analysis)
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword(".", path, acc)
      print_with_offset(
        label,
        list.append(path, [0]),
        Default,
        acc,
        info,
        analysis,
      )
    }
    e.Apply(e.Apply(e.Cons, item), tail) -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword("[", path, acc)
      let #(acc, info) =
        print_block(
          item,
          Situ(list.append(path, [0, 1])),
          br,
          acc,
          info,
          analysis,
        )
      print_tail(tail, list.append(path, [1]), br, acc, info, analysis)
    }
    // It works using both here because a record should always end in empty
    // and overwrite always a variable
    e.Apply(e.Apply(e.Extend(label), item), tail)
    | e.Apply(e.Apply(e.Overwrite(label), item), tail) -> {
      // let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword("{", path, acc)
      let #(acc, info) =
        print_with_offset(
          label,
          list.append(path, []),
          Union,
          acc,
          info,
          analysis,
        )
      let acc = print_keyword(": ", path, acc)
      let #(acc, info) =
        print_block(
          item,
          Situ(list.append(path, [0, 1])),
          br,
          acc,
          info,
          analysis,
        )
      print_extend(tail, list.append(path, [1]), br, acc, info, analysis)
    }
    e.Apply(e.Apply(e.Case(label), item), tail) -> {
      let acc = print_keyword("match {", path, acc)
      let br_inner = string.append(br, "  ")
      let acc = print_keyword(br_inner, path, acc)
      let #(acc, info) =
        print_with_offset(
          label,
          list.append(path, []),
          Union,
          acc,
          info,
          analysis,
        )
      let acc = print_keyword(" ", path, acc)
      let #(acc, info) =
        print_block(
          item,
          Situ(list.append(path, [0, 1])),
          br_inner,
          acc,
          info,
          analysis,
        )
      print_match(
        tail,
        list.append(path, [1]),
        br,
        br_inner,
        acc,
        info,
        analysis,
      )
    }
    e.Apply(func, arg) -> {
      let #(acc, info) =
        print_block(func, Situ(list.append(path, [0])), br, acc, info, analysis)
      let info = map.insert(info, path_to_string(path), list.length(acc))

      let acc = print_keyword("(", path, acc)
      let #(acc, info) =
        print_block(arg, Situ(list.append(path, [1])), br, acc, info, analysis)

      let acc = print_keyword(")", path, acc)
      #(acc, info)
    }
    e.Let(label, value, then) -> {
      let acc = print_keyword("let ", path, acc)
      let #(acc, info) =
        print_with_offset(label, path, Default, acc, info, analysis)
      let acc = print_keyword(" = ", path, acc)
      let #(acc, info) =
        print_block(
          value,
          Situ(list.append(path, [0])),
          br,
          acc,
          info,
          analysis,
        )
      let acc = print_keyword(br, path, acc)
      do_print(then, Situ(list.append(path, [1])), br, acc, info, analysis)
    }
    e.Variable(label) ->
      print_with_offset(label, path, Default, acc, info, analysis)
    e.Vacant(_) -> {
      let #(sub, _next, types) = analysis
      let content = case map.get(types, list.reverse(path)) {
        Error(Nil) -> "todo"
        Ok(inferred) ->
          case inferred {
            Ok(t) -> {
              let t = t.resolve(t, sub)
              type_.render_type(t)
            }

            Error(#(r, t1, t2)) -> type_.render_failure(r, t1, t2)
          }
      }
      print_with_offset(content, path, Hole, acc, info, analysis)
    }
    e.Integer(value) ->
      print_with_offset(
        int.to_string(value),
        path,
        Integer,
        acc,
        info,
        analysis,
      )
    e.Binary(value) -> {
      let acc = [#("\"", path, -1, String), ..acc]
      // Maybe I don't need to append " if looking left
      print_with_offset(
        string.append(value, "\""),
        path,
        String,
        acc,
        info,
        analysis,
      )
    }
    e.Tail -> {
      let info = map.insert(info, path_to_string(path), list.length(acc) + 1)
      let acc = print_keyword("[]", path, acc)
      #(acc, info)
    }
    e.Cons -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword("cons", path, acc)
      #(acc, info)
    }
    e.Empty -> {
      let info = map.insert(info, path_to_string(path), list.length(acc) + 1)
      let acc = print_keyword("{}", path, acc)
      #(acc, info)
    }
    e.Extend(label) -> {
      // TODO better name than union
      let acc = [#("+", path, -1, Union), ..acc]
      print_with_offset(label, path, Union, acc, info, analysis)
    }
    e.Select(label) -> {
      // TODO better name than union
      let acc = [#(".", path, -1, Union), ..acc]
      print_with_offset(label, path, Union, acc, info, analysis)
    }
    e.Overwrite(label) -> {
      // TODO better name than union
      let acc = [#("=", path, -1, Union), ..acc]
      print_with_offset(label, path, Union, acc, info, analysis)
    }
    e.Tag(label) -> {
      // The idea was marking something as a tag
      // let acc = [#("=", path, -1, Union), ..acc]
      print_with_offset(label, path, Union, acc, info, analysis)
    }
    e.Case(label) -> {
      let acc = [#("|", path, -1, Union), ..acc]
      print_with_offset(label, path, Union, acc, info, analysis)
    }
    e.NoCases -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword("----", path, acc)
      #(acc, info)
    }
    e.Perform(label) -> {
      let acc = print_keyword("perform ", path, acc)
      print_with_offset(label, path, Effect, acc, info, analysis)
    }
    e.Handle(label) -> {
      let acc = print_keyword("handle ", path, acc)
      print_with_offset(label, path, Effect, acc, info, analysis)
    }
    e.Builtin(value) ->
      print_with_offset(value, path, Builtin, acc, info, analysis)
  }
}

fn print_block(source, situ, br, acc, info, analysis) {
  let Situ(path) = situ
  case source {
    e.Let(_, _, _) -> {
      let br_inner = string.append(br, "  ")
      let acc = print_keyword(string.append("{", br_inner), path, acc)
      let #(acc, info) = do_print(source, situ, br_inner, acc, info, analysis)
      let acc = print_keyword(string.append(br, "}"), path, acc)
      #(acc, info)
    }
    _ -> do_print(source, situ, br, acc, info, analysis)
  }
}

fn print_tail(exp, path, br, acc, info, analysis) {
  case exp {
    e.Tail -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword("]", path, acc)
      #(acc, info)
    }
    e.Apply(e.Apply(e.Cons, item), tail) -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword(", ", path, acc)
      let #(acc, info) =
        print_block(
          item,
          Situ(list.append(path, [0, 1])),
          br,
          acc,
          info,
          analysis,
        )
      print_tail(tail, list.append(path, [1]), br, acc, info, analysis)
    }
    _ -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword(", ..", path, acc)
      let #(acc, info) =
        print_block(exp, Situ(path: path), br, acc, info, analysis)
      let acc = print_keyword("]", path, acc)
      #(acc, info)
    }
  }
}

fn print_extend(exp, path, br, acc, info, analysis) {
  case exp {
    e.Empty -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword("}", path, acc)
      #(acc, info)
    }
    e.Apply(e.Apply(e.Extend(label), item), tail)
    | e.Apply(e.Apply(e.Overwrite(label), item), tail) -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword(", ", path, acc)
      let #(acc, info) =
        print_with_offset(
          label,
          list.append(path, []),
          Union,
          acc,
          info,
          analysis,
        )
      let acc = print_keyword(": ", path, acc)
      let #(acc, info) =
        print_block(
          item,
          Situ(list.append(path, [0, 1])),
          br,
          acc,
          info,
          analysis,
        )
      print_extend(tail, list.append(path, [1]), br, acc, info, analysis)
    }
    _ -> {
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let acc = print_keyword(", ..", path, acc)
      let #(acc, info) =
        print_block(exp, Situ(path: path), br, acc, info, analysis)
      let acc = print_keyword("}", path, acc)
      #(acc, info)
    }
  }
}

fn print_match(exp, path, br, br_inner, acc, info, analysis) {
  case exp {
    e.NoCases -> {
      let acc = print_keyword(br, path, acc)
      let info = map.insert(info, path_to_string(path), list.length(acc))

      let acc = print_keyword("}", path, acc)
      #(acc, info)
    }
    e.Apply(e.Apply(e.Case(label), item), tail) -> {
      let acc = print_keyword(br_inner, path, acc)
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let #(acc, info) =
        print_with_offset(
          label,
          list.append(path, []),
          Union,
          acc,
          info,
          analysis,
        )
      let acc = print_keyword(" ", path, acc)
      let #(acc, info) =
        print_block(
          item,
          Situ(list.append(path, [0, 1])),
          br_inner,
          acc,
          info,
          analysis,
        )
      print_match(
        tail,
        list.append(path, [1]),
        br,
        br_inner,
        acc,
        info,
        analysis,
      )
    }
    _ -> {
      let acc = print_keyword(br_inner, path, acc)
      let info = map.insert(info, path_to_string(path), list.length(acc))
      let #(acc, info) =
        print_block(exp, Situ(path: path), br, acc, info, analysis)
      let acc = print_keyword(br, path, acc)
      let acc = print_keyword("}", path, acc)
      #(acc, info)
    }
  }
}

pub fn print_keyword(keyword, path, acc) {
  list.fold(
    string.to_graphemes(keyword),
    acc,
    fn(acc, ch) { [#(ch, path, -1, Keyword), ..acc] },
  )
}

pub fn print_with_offset(content, path, style, acc, info, _analysis) {
  let info = map.insert(info, path_to_string(path), list.length(acc))
  let #(content, style) = case content {
    "" -> #("_", Missing)
    _ -> #(content, style)
  }
  let acc =
    list.index_fold(
      string.to_graphemes(content),
      acc,
      fn(acc, ch, i) { [#(ch, path, i, style), ..acc] },
    )
  #(acc, info)
}

pub fn path_to_string(path) {
  list.map(path, int.to_string)
  |> string.join("j")
}
