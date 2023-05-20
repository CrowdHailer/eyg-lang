import gleam/io
import gleam/list
import gleam/listx
import gleam/map
import gleam/result
import gleam/string
import gleam/stringx
import eygir/expression as e
import easel/print

// Not a full app
// Widget is another name element/panel
// Embed if I have a separate app file

pub type Embed {
  Embed(
    source: e.Expression,
    rendered: #(List(print.Rendered), map.Map(String, Int)),
  )
}

pub fn source() {
  e.Let("foo", e.Binary("hello"), e.Let("y", e.Integer(100), e.Empty))
}

pub fn init() {
  let s = source()
  let rendered = print.print(s)
  Embed(s, rendered)
}

pub fn child(expression, index) {
  case expression, index {
    e.Lambda(param, body), 0 -> Ok(#(body, e.Lambda(param, _)))
    e.Apply(func, arg), 0 -> Ok(#(func, e.Apply(_, arg)))
    e.Apply(func, arg), 1 -> Ok(#(arg, e.Apply(func, _)))
    e.Let(label, value, then), 0 -> Ok(#(value, e.Let(label, _, then)))
    e.Let(label, value, then), 1 -> Ok(#(then, e.Let(label, value, _)))
    _, _ -> Error(Nil)
  }
  // This is one of the things that would be harder with overwrite having children
}

pub fn zipper(expression, path) {
  do_zipper(expression, path, [])
}

fn do_zipper(expression, path, acc) {
  case path {
    [] ->
      Ok(#(
        expression,
        fn(new) { list.fold(acc, new, fn(element, build) { build(element) }) },
      ))
    [index, ..path] -> {
      use #(child, rebuild) <- result.then(child(expression, index))
      do_zipper(child, path, [rebuild, ..acc])
    }
  }
}

pub fn insert_text(state: Embed, data, start, end) {
  let assert Ok(#(_ch, path, cut_start, _style)) =
    list.at(state.rendered.0, start)
  let assert Ok(#(_ch, p2, cut_end, _style)) = list.at(state.rendered.0, end)
  case path != p2 || cut_start < 0 {
    True -> {
      #(state, start)
    }
    _ -> {
      let assert Ok(#(target, rezip)) = zipper(state.source, path)
      // always the same path
      let #(new, offset) = case target {
        e.Let(label, value, then) -> {
          let label = stringx.replace_at(label, cut_start, cut_end, data)
          #(e.Let(label, value, then), cut_start + string.length(data))
        }
        e.Binary(value) -> {
          let value = stringx.replace_at(value, cut_start, cut_end, data)
          #(e.Binary(value), cut_start + string.length(data))
        }
        node -> #(node, cut_start)
      }
      let source = rezip(new)
      // TODO move to update source
      let rendered = print.print(source)
      // zip and target
      // io.debug(rendered)

      // update source source have a offset function
      let assert Ok(start) = map.get(rendered.1, print.path_to_string(path))
      #(Embed(source, rendered), start + offset)
    }
  }
}

pub fn insert_paragraph(index, state: Embed) {
  let assert Ok(#(_ch, path, offset, _style)) = list.at(state.rendered.0, index)
  let assert Ok(#(target, rezip)) = zipper(state.source, path)

  let new = case target {
    e.Let(label, value, then) -> {
      e.Let(label, value, e.Let("", e.Vacant(""), then))
    }
    node -> e.Let("", node, e.Vacant(""))
  }
  let source = rezip(new)
  let rendered = print.print(source)
  let assert Ok(start) =
    map.get(rendered.1, print.path_to_string(list.append(path, [1])))
  #(Embed(source, rendered), start)
}

pub fn html(embed: Embed) {
  embed.rendered.0
  |> group
  |> to_html()
}

fn to_html(sections) {
  list.fold(
    sections,
    "",
    fn(acc, section) {
      let #(style, letters) = section
      let class = case style {
        print.Default -> ""
        print.Keyword -> "text-gray-500"
        print.Missing -> "text-pink-3"
        print.Hole -> "text-orange-4 font-bold"
        print.Integer -> "text-purple-4"
        print.String -> "text-green-4"
        print.Union -> "text-blue-3"
        print.Effect -> "text-yellow02"
      }
      string.concat([
        acc,
        "<span class=\"",
        class,
        "\">",
        string.concat(letters),
        "</span>",
      ])
    },
  )
}

fn group(rendered: List(print.Rendered)) {
  // list.fold(rendered, #([[first.0]], first.2), fn(state) { 
  //   let #(store,)
  //  })
  case rendered {
    [] -> []
    [#(ch, _path, offset, style), ..rendered] ->
      do_group(rendered, [ch], [], style)
  }
}

fn do_group(rest, current, acc, style) {
  case rest {
    [] -> list.reverse([#(style, list.reverse(current)), ..acc])
    [#(ch, _path, _offset, s), ..rest] ->
      case s == style {
        True -> do_group(rest, [ch, ..current], acc, style)
        False ->
          do_group(rest, [ch], [#(style, list.reverse(current)), ..acc], s)
      }
  }
}
