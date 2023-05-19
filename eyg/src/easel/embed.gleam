import gleam/io
import gleam/list
import gleam/listx
import gleam/map
import gleam/result
import gleam/string
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
  e.Let("x", e.Binary("hello"), e.Let("y", e.Integer(100), e.Empty))
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

pub fn insert_text(state: Embed, data, index) {
  let assert Ok(#(_ch, path, offset, _style)) = list.at(state.rendered.0, index)
  let assert Ok(#(target, rezip)) = zipper(state.source, path)
  // always the same path
  let #(new, offset) = case target {
    e.Let(label, value, then) -> {
      let label =
        string.to_graphemes(label)
        |> listx.insert_at(offset, string.to_graphemes(data))
        |> string.concat
      #(e.Let(label, value, then), offset + string.length(data))
    }
    node -> #(node, offset)
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

pub fn insert_paragraph(index, state: Embed) {
  // TODO look up in rendered
  // offset and path and do action
  // Need my list cursor
  // let rendered = state.rendered
  // let pre = list.take(rendered, index)
  // let post = list.drop(rendered, index)
  // Embed(list.flatten([pre, [], post]))
  todo("paragrphj")
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
        True -> "bold"
        False -> "normal"
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
