import gleam/list
import lustre/attribute as a
import lustre/element
import lustre/element/html as h

pub fn render() {
  h.div([], list.map(bindings(), key_binding))
}

fn key_binding(binding) {
  let #(k, action) = binding
  h.div([a.class("")], [
    h.span([a.class("font-bold")], [element.text(k)]),
    h.span([], [element.text(": ")]),
    h.span([], [element.text(action)]),
  ])
}

fn bindings() {
  [
    #("?", "show/hide help"),
    #("SPACE", "jump to next vacant"),
    #("w", "call a function with this term"),
    #("E", "insert an assignment before this term"),
    #("e", "assign this term"),
    #("r", "create a record"),
    #("t", "create a tagged term"),
    #("y", "copy"),
    #("Y", "paste"),
    // "u" ->
    #("i", "edit this term"),
    #("o", "overwrite record fields"),
    #("p", "create a perform effect"),
    #("a", "increase the selection"),
    #("s", "create a string"),
    #("d", "delete this code"),
    #("f", "wrap in a function"),
    #("g", "select a field"),
    #("h", "create an effect handler"),
    #("j", "insert a builtin function"),
    #("k", "collapse/uncollapse code section"),
    #("l", "create a list"),
    #("#", "insert a reference"),
    // "z" -> TODO need to use the same history stuff
    // "x" ->
    #("c", "call function this function"),
    #("v", "create a variable"),
    #("b", "create a array of bytes"),
    #("n", "create a number"),
    #("m", "create a match expression"),
    #("M", "insert an open match expression"),
    #(",", "add element in a list"),
    #(".", "open a list for extension"),
  ]
}
