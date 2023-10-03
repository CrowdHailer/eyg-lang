import gleam/int
import gleam/list
import gleam/string

pub fn text(value) {
  fn(listeners) { #(value, listeners) }
}

pub fn el(tag, attributes, children) {
  fn(listeners) {
    let #(listeners, attributes) =
      list.map_fold(
        attributes,
        listeners,
        fn(acc, attribute) {
          let #(#(key, value), acc) = attribute(acc)

          #(acc, string.concat([key, "=\"", value, "\""]))
        },
      )
    let #(listeners, children) =
      list.map_fold(
        children,
        listeners,
        fn(acc, child) {
          let #(rendered, acc) = child(acc)
          #(acc, rendered)
        },
      )

    let tag_and_attributes = string.join([tag, ..attributes], " ")

    let rendered =
      string.concat(["<", tag_and_attributes, ">", ..children])
      |> string.append("</")
      |> string.append(tag)
      |> string.append(">")

    #(rendered, listeners)
  }
}

pub fn div(attributes, children) {
  el("div", attributes, children)
}

pub fn button(attributes, children) {
  el("button", attributes, children)
}

pub fn onclick(action) {
  fn(listeners) {
    let id = list.length(listeners)
    let listeners = [action, ..listeners]
    #(#("[data-click]", int.to_string(id)), listeners)
  }
}
