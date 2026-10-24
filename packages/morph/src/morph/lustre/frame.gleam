import gleam/list
import gleam/option.{type Option, None}

pub type Span {
  Span(
    class: List(String),
    rev: Option(List(Int)),
    text: String,
    focus: Bool,
    error: Bool,
    title: Option(String),
  )
}

pub fn span(class, rev, text) {
  Span(class:, rev:, text:, focus: False, error: False, title: None)
}

pub fn with_title(span: Span, title: String) {
  Span(..span, title: option.Some(title))
}

// component, block panel
// enclosed bare clad
// prepend spans doesnt work on bare item
pub type Frame {
  Multiline(List(Span), List(Frame), List(Span))
  Inline(List(Span))
  Statements(List(Frame))
}

fn is_inline(m) {
  case m {
    Inline(spans) -> Ok(spans)
    _ -> Error(Nil)
  }
}

pub fn line_height(frame) {
  case frame {
    Inline(_) -> 1
    Multiline(_, inner, _) -> list.length(inner)
    Statements(inner) -> list.length(inner)
  }
}

pub fn all_inline(ms) {
  list.try_map(ms, is_inline)
}

pub fn prepend_spans(new, m) {
  case m {
    Inline(spans) -> Inline(list.append(new, spans))
    Multiline(pre, inner, post) -> Multiline(list.append(new, pre), inner, post)
    Statements(inner) ->
      prepend_spans(
        new,
        Multiline([span([], None, "{")], inner, [span([], None, "}")]),
      )
  }
}

pub fn append_spans(m, new) {
  case m {
    Inline(spans) -> Inline(list.append(spans, new))
    Multiline(pre, inner, post) -> Multiline(pre, inner, list.append(post, new))
    Statements(inner) ->
      append_spans(
        Multiline([span([], None, "{")], inner, [span([], None, "}")]),
        new,
      )
  }
}

pub fn join(a, b) {
  case a, b {
    Inline(spans), b -> prepend_spans(spans, b)
    a, Inline(spans) -> append_spans(a, spans)
    Multiline(pre, inner_a, span_a), Multiline(span_b, inner_b, post) -> {
      let middle = Inline(list.append(span_a, span_b))
      let inner = list.flatten([inner_a, [middle], inner_b])
      Multiline(pre, inner, post)
    }
    _, _ -> panic as "joining statements should not occur"
  }
}

pub fn delimit(frames, delimiter) {
  case list.reverse(frames) {
    [] -> []
    [last, ..rest] -> {
      let rest = list.map(rest, append_spans(_, [span([], None, delimiter)]))
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
    Inline(spans) -> Inline(spans)
    Multiline([], inner, []) -> Statements(inner)
    Multiline(pre, inner, post) ->
      Statements([
        Inline(pre),
        // TODO these need indenting
        Statements(inner),
        Inline(post),
      ])
    Statements(inner) -> Statements(inner)
  }
}
// fn indent(inner) {
//   h.div([a.styles([#("padding-left", "2ch")])], inner)
// }
