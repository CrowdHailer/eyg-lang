import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e

pub type Style {
  Default
  Keyword
  Missing
  Hole
  Integer
  String
  Union
  Effect
}

pub type Rendered =
  #(String, List(Int), Int, Style)

type Situ {
  Situ(path: List(Int))
}

pub fn print(source) {
  let #(acc, info) = do_print(source, Situ([]), [], map.new())
  #(list.reverse(acc), info)
}

fn do_print(source, situ, acc, info) {
  let Situ(path) = situ
  case source {
    e.Lambda(param, body) -> {
      let #(acc, info) = print_with_offset(param, path, Default, acc, info)
      let acc = print_keyword(" -> ", path, acc)
      do_print(body, Situ(list.append(path, [0])), acc, info)
    }
    // e.Call(func, arg) -> 
    e.Let(label, value, then) -> {
      let acc = print_keyword("let ", path, acc)
      let #(acc, info) = print_with_offset(label, path, Default, acc, info)
      let acc = print_keyword(" = ", path, acc)
      let #(acc, info) =
        do_print(value, Situ(list.append(path, [0])), acc, info)
      let acc = print_keyword("\n", path, acc)
      do_print(then, Situ(list.append(path, [1])), acc, info)
    }
    // e.Variable(_) -> #(acc, info)
    e.Vacant(_) -> print_with_offset("todo", path, Hole, acc, info)
    e.Binary(value) -> {
      let acc = [#("\"", path, -1, String), ..acc]
      // Maybe I don't need to append " if looking left
      print_with_offset(string.append(value, "\""), path, String, acc, info)
    }
    e.Integer(value) ->
      print_with_offset(int.to_string(value), path, Integer, acc, info)
    _ -> #(acc, info)
  }
}

pub fn print_keyword(keyword, path, acc) {
  list.fold(
    string.to_graphemes(keyword),
    acc,
    fn(acc, ch) { [#(ch, path, -1, Keyword), ..acc] },
  )
}

pub fn print_with_offset(content, path, style, acc, info) {
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
