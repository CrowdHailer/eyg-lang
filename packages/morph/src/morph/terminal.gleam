//// The structural editor in a terminal, its key bindings and its code drawn as etui lines.
//// A terminal interface keeps its own modes, such as entering text, and uses these for navigating code.

import etui/span
import etui/style
import eyg/analysis/type_/isomorphic as t
import gleam/list
import morph/buffer.{type Buffer}
import morph/lustre/frame
import morph/manipulation as m

/// What a key does to the code.
pub type Binding {
  Move(name: String, move: fn(Buffer) -> Result(Buffer, Nil))
  Edit(m.Operation)
}

/// The binding of a key while navigating code.
/// `effects` are offered when performing or handling an effect, `packages` when choosing a release.
pub fn binding(
  key: String,
  effects: List(#(String, #(t.Type(Int), t.Type(Int)))),
  packages: List(#(String, Int)),
) -> Result(Binding, Nil) {
  case key {
    "right" -> Ok(Move("move right", buffer.next))
    "left" -> Ok(Move("move left", buffer.previous))
    "up" -> Ok(Move("move up", buffer.up))
    "down" -> Ok(Move("move down", buffer.down))
    "a" -> Ok(Move("increase selection", buffer.increase))
    "k" -> Ok(Move("toggle", buffer.toggle_open))
    " " -> Ok(Move("Jump to vacant", buffer.next_vacant))
    "w" -> Ok(Edit(m.call_with()))
    "E" -> Ok(Edit(m.assign_before()))
    "e" -> Ok(Edit(m.assign()))
    "R" -> Ok(Edit(m.create_empty_record()))
    "r" -> Ok(Edit(m.create_record()))
    "t" -> Ok(Edit(m.insert_tag()))
    "i" -> Ok(Edit(m.insert()))
    "o" -> Ok(Edit(m.overwrite()))
    "p" -> Ok(Edit(m.perform(effects)))
    "s" -> Ok(Edit(m.insert_string()))
    "d" -> Ok(Edit(m.delete()))
    "f" -> Ok(Edit(m.insert_function()))
    "g" -> Ok(Edit(m.select_field()))
    "h" -> Ok(Edit(m.insert_handle(effects)))
    "j" -> Ok(Edit(m.insert_builtin()))
    "L" -> Ok(Edit(m.create_empty_list()))
    "l" -> Ok(Edit(m.create_list()))
    "@" -> Ok(Edit(m.choose_release(packages)))
    "#" -> Ok(Edit(m.insert_reference()))
    "Z" -> Ok(Edit(m.redo()))
    "z" -> Ok(Edit(m.undo()))
    "x" -> Ok(Edit(m.spread()))
    "c" -> Ok(Edit(m.call_function()))
    "C" -> Ok(Edit(m.call_once()))
    "b" -> Ok(Edit(m.insert_binary()))
    "n" -> Ok(Edit(m.insert_integer()))
    "m" -> Ok(Edit(m.insert_case()))
    "v" -> Ok(Edit(m.insert_variable()))
    "<" -> Ok(Edit(m.insert_before()))
    ">" -> Ok(Edit(m.insert_after()))
    _ -> Error(Nil)
  }
}

/// The lines of code in a frame, coloured by syntax.
/// The focus is reversed, or dimmed and underlined when the code is not `active`.
pub fn lines(value: frame.Frame, active: Bool) -> List(span.Line) {
  case value {
    frame.Inline(spans) -> list.wrap(line(spans, active))
    frame.Multiline([], inner, []) | frame.Statements(inner) ->
      list.flat_map(inner, lines(_, active))
    frame.Multiline(pre, inner, post) -> {
      // Indent the whole selected structure, but not a selected child alone.
      // Its boundary lines may also contain unselected context or delimiters.
      let focused =
        list.any(pre, fn(s) { s.focus })
        && list.any(post, fn(s) { s.focus })
        && list.all(inner, frame.fully_focused)
      let indent =
        span.span_styled(
          "  ",
          focus_style(style.default_style(), focused, active),
        )
      list.flatten([
        [line(pre, active)],
        list.flat_map(inner, lines(_, active))
          |> list.map(fn(line) {
            span.Line(..line, spans: [indent, ..line.spans])
          }),
        [line(post, active)],
      ])
    }
  }
}

fn line(spans: List(frame.Span), active: Bool) -> span.Line {
  let red = style.Rgb(255, 0, 0)

  list.map(spans, fn(span) {
    let base = syntax_style(span.token_type)
    let style = case span.error {
      True ->
        base
        |> style.add_modifier(style.underline())
        |> style.with_underline_color(red)
      False -> base
    }
    let style = focus_style(style, span.focus, active)
    span.span_styled(span.text, style)
  })
  |> span.line_new
}

pub fn focus_style(
  base: style.Style,
  focused: Bool,
  active: Bool,
) -> style.Style {
  case focused, active {
    False, _ -> base
    True, True ->
      base
      |> style.with_fg(style.Default)
      |> style.with_bg(style.Default)
      |> style.add_modifier(style.reverse())
    True, False ->
      base
      |> style.add_modifier(style.dim())
      |> style.add_modifier(style.underline())
  }
}

fn syntax_style(token_type: frame.TokenType) -> style.Style {
  case token_type {
    frame.Plain | frame.Punctuation -> style.default_style()

    frame.Comment ->
      style.default_style()
      |> style.add_modifier(style.dim())

    frame.Number | frame.Symbol ->
      style.default_style()
      |> style.with_fg(style.Indexed(5))

    frame.String | frame.Char | frame.Builtin ->
      style.default_style()
      |> style.with_fg(style.Indexed(2))

    frame.Keyword ->
      style.default_style()
      |> style.with_fg(style.Indexed(6))

    frame.Variable ->
      style.default_style()
      |> style.with_fg(style.Indexed(3))

    frame.Important ->
      style.default_style()
      |> style.with_fg(style.Indexed(3))
      |> style.add_modifier(style.bold())
    frame.ClassName ->
      style.default_style()
      |> style.with_fg(style.Indexed(12))
      |> style.add_modifier(style.bold())
  }
}
