import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as a
import lustre/element.{type Element}
import lustre/element/html as h
import morph/lustre/frame as f
import morph/lustre/render
import morph/projection as p

/// Render an expression with its syntax classes, AST paths, and errors.
pub fn expression(exp, rev, errors) -> Element(msg) {
  render.expression(exp, rev, errors)
  |> frame
}

/// Render top-level statements, omitting a vacant continuation.
pub fn statements(code, errors) -> List(Element(msg)) {
  render.statements(code, errors)
  |> list.map(frame)
}

/// Render an unwrapped top-level block, including its continuation.
pub fn top(code, errors) -> List(Element(msg)) {
  render.top(code, errors)
  |> list.map(frame)
}

/// Render the focus and its surrounding context, then produce Lustre elements.
pub fn projection(
  proj: p.Projection,
  kind: render.RenderKind,
  errors,
) -> Element(msg) {
  render.projection(proj, kind, errors)
  |> frame
}

/// Interpret the chosen layout without flattening its indentation boundaries.
pub fn frame(value: f.Frame) -> Element(msg) {
  render_frame(value, False)
}

fn render_frame(value, inherited_focus) {
  case value {
    f.Inline(spans) -> h.div([], render_spans(spans, inherited_focus))
    f.Multiline([], inner, []) | f.Statements(inner) ->
      h.div([], body(inner, inherited_focus, True))
    f.Multiline(pre, inner, post) ->
      h.div([], [
        h.div([], render_spans(pre, inherited_focus)),
        h.div(
          [a.styles([#("padding-left", "2ch")])],
          body(
            inner,
            inherited_focus,
            list.any(pre, fn(s) { s.focus })
              && list.any(post, fn(s) { s.focus }),
          ),
        ),
        h.div([], render_spans(post, inherited_focus)),
      ])
  }
}

// Recover a continuous selected body at the HTML boundary. The frame tree
// remains untouched, and a selected child alone does not select its parent.
fn body(children, inherited_focus, selected_boundaries) {
  let focused =
    !inherited_focus
    && selected_boundaries
    && children != []
    && list.all(children, f.fully_focused)
  let content = list.map(children, render_frame(_, inherited_focus || focused))
  case focused {
    True -> [h.div([a.styles(focus_styles())], content)]
    False -> content
  }
}

fn render_spans(values: List(f.Span), inherited_focus: Bool) {
  values
  |> list.chunk(fn(s) { s.error })
  |> list.flat_map(fn(group) {
    case group {
      [first, _, ..] if first.error -> [
        h.span(
          [a.styles([#("text-decoration", "underline red wavy")])],
          group
            |> list.map(fn(s) { f.Span(..s, error: False) })
            |> focus_spans(inherited_focus),
        ),
      ]
      _ -> focus_spans(group, inherited_focus)
    }
  })
}

fn focus_spans(values: List(f.Span), inherited_focus: Bool) {
  values
  |> list.chunk(fn(s) { s.focus && !inherited_focus })
  |> list.flat_map(fn(group) {
    case group {
      [first, _, ..] if first.focus && !inherited_focus -> [
        h.span([a.styles(focus_styles())], list.map(group, span(_, True))),
      ]
      _ -> list.map(group, span(_, inherited_focus))
    }
  })
}

fn focus_styles() {
  [
    #("padding", ".25rem"),
    #("background-color", "rgb(167, 243, 208)"),
    #("border-radius", ".25rem"),
    #("margin", "-.25rem"),
  ]
}

fn span(value: f.Span, inherited_focus: Bool) -> Element(msg) {
  let classes = case value.token_type {
    f.Plain -> []
    f.Comment -> [a.class("token comment")]
    f.Punctuation -> [a.class("token punctuation")]
    f.Important -> [a.class("token important")]
    f.Char -> [a.class("token char")]
    f.Number -> [a.class("token number")]
    f.String -> [a.class("token string")]
    f.ClassName -> [a.class("token class-name")]
    f.Keyword -> [a.class("token keyword")]
    f.Builtin -> [a.class("token builtin")]
    f.Symbol -> [a.class("token symbol")]
    f.Variable -> [a.class("token variable")]
  }
  let path = case value.rev {
    None -> []
    Some(rev) -> [
      a.attribute("data-rev", string.join(list.map(rev, int.to_string), ",")),
    ]
  }
  let title = case value.title {
    None -> []
    Some(title) -> [a.title(title)]
  }
  let focus = case value.focus && !inherited_focus {
    False -> []
    True -> focus_styles()
  }
  let error = case value.error {
    False -> []
    True -> [#("text-decoration", "underline red wavy")]
  }
  let styles = case list.append(focus, error) {
    [] -> []
    styles -> [a.styles(styles)]
  }
  case list.flatten([classes, path, title, styles]) {
    [] -> element.text(value.text)
    attributes -> h.span(attributes, [element.text(value.text)])
  }
}
