import gleam/list
import lustre/attribute as a
import lustre/element/html as h
import lustre/element.{text}

// component, block panel
// enclosed bare clad
// prepend spans doesnt work on bare item
pub type Frame(a) {
  Multiline(
    List(element.Element(a)),
    List(element.Element(a)),
    List(element.Element(a)),
  )
  Inline(List(element.Element(a)))
}

fn is_inline(m) {
  case m {
    Inline(spans) -> Ok(spans)
    _ -> Error(Nil)
  }
}

pub fn all_inline(ms) {
  list.try_map(ms, is_inline)
}

pub fn prepend_spans(new, m) {
  case m {
    Inline(spans) -> Inline(list.append(new, spans))
    Multiline(pre, inner, post) -> Multiline(list.append(new, pre), inner, post)
  }
}

pub fn append_spans(m, new) {
  case m {
    Inline(spans) -> Inline(list.append(spans, new))
    Multiline(pre, inner, post) -> Multiline(pre, inner, list.append(post, new))
  }
}

pub fn delimit(frames, delimiter) {
  case list.reverse(frames) {
    [] -> []
    [last, ..rest] -> {
      let rest = list.map(rest, append_spans(_, [text(delimiter)]))
      list.reverse([last, ..rest])
    }
  }
}

// Call to_divs but its a single div
// could return unwrapped divs but what about indent.
// have indent as an option
// wrap each line thing in it's own div
pub fn to_fat_line(exp) {
  case exp {
    Inline(spans) -> h.div([], spans)
    Multiline([], inner, []) -> h.div([], inner)
    Multiline(pre, inner, post) ->
      h.div([], [h.div([], pre), indent(inner), h.div([], post)])
  }
}

fn indent(inner) {
  h.div([a.style([#("padding-left", "2ch")])], inner)
}

pub fn to_fat_lines(lines) {
  list.map(lines, to_fat_line)
}
