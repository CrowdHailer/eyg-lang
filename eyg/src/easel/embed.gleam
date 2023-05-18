import gleam/list
import gleam/string
import eygir/expression as e

// Not a full app
// Widget is another name element/panel
// Embed if I have a separate app file

pub fn initial() {
  "hello"
}

type Rendered =
  #(String, Int, Bool)

pub type Embed {
  Embed(
    // source: e.Node
    rendered: List(Rendered),
  )
}

pub fn init() {
  [#("a", 0, False), #("\n", 1, False), #("b", 1, False), #("c", 0, True)]
  |> Embed
}

pub fn insert_paragraph(index, state: Embed) {
  // TODO look up in rendered
  // offset and path and do action
  // Need my list cursor
  let rendered = state.rendered
  let pre = list.take(rendered, index)
  let post = list.drop(rendered, index)
  Embed(list.flatten([pre, [#("\n", 1, False)], post]))
}

pub fn html(embed: Embed) {
  embed.rendered
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

fn group(rendered: List(Rendered)) {
  // list.fold(rendered, #([[first.0]], first.2), fn(state) { 
  //   let #(store,)
  //  })
  case rendered {
    [] -> []
    [#(ch, _, style), ..rendered] -> do_group(rendered, [ch], [], style)
  }
}

fn do_group(rest, current, acc, style) {
  case rest {
    [] -> list.reverse([#(style, list.reverse(current)), ..acc])
    [#(ch, _, s), ..rest] ->
      case s == style {
        True -> do_group(rest, [ch, ..current], acc, style)
        False ->
          do_group(rest, [ch], [#(style, list.reverse(current)), ..acc], s)
      }
  }
}
