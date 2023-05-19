import gleam/int
import gleam/list
import gleam/map
import gleam/string
import eygir/expression as e

pub type Style {
  Keyword
  Label
}

pub type Rendered =
  #(String, List(Int), Int, Bool)

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
    // e.Lambda(param, body) -> acc
    // e.Call(func, arg) -> 
    e.Let(label, value, then) -> {
      let acc = print_keyword("let ", path, acc)
      let #(acc, info) = print_with_offset(label, path, acc, info)
      let acc = print_keyword(" = ", path, acc)
      let #(acc, info) =
        do_print(value, Situ(list.append(path, [0])), acc, info)
      let acc = print_keyword("\n", path, acc)
      do_print(then, Situ(list.append(path, [1])), acc, info)
    }
    // e.Variable(_) -> #(acc, info)
    e.Integer(value) -> print_with_offset(int.to_string(value), path, acc, info)
    _ -> #(acc, info)
  }
}

pub fn print_keyword(keyword, path, acc) {
  list.fold(
    string.to_graphemes(keyword),
    acc,
    fn(acc, ch) { [#(ch, path, -1, False), ..acc] },
  )
}

pub fn print_with_offset(label, path, acc, info) {
  let info = map.insert(info, path_to_string(path), list.length(acc))
  let acc =
    list.index_fold(
      string.to_graphemes(label),
      acc,
      fn(acc, ch, i) { [#(ch, path, i, True), ..acc] },
    )
  #(acc, info)
}

pub fn path_to_string(path) {
  list.map(path, int.to_string)
  |> string.join("j")
}
