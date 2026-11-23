//// The structural editor in a terminal, its key bindings and its code drawn as etui lines.
//// A terminal interface keeps its own modes, such as entering text, and uses these for navigating code.
//// EYG text is highlighted with the same colours, see `highlight`.

import etui/span
import etui/style
import eyg/analysis/type_/isomorphic as t
import eyg/parser/lexer
import eyg/parser/token
import gleam/bit_array
import gleam/list
import gleam/result
import gleam/string
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

/// EYG text coloured as code is coloured in the structural editor, the spans of each of its lines.
/// The text is kept exactly, invalid tokens are underlined.
pub fn highlight(source: String) -> List(List(span.Span)) {
  let bits = bit_array.from_string(source)
  let tokens = lexer.lex(source)
  let ends =
    list.drop(tokens, 1)
    |> list.map(fn(token) { token.1 })
    |> list.append([bit_array.byte_size(bits)])
  let #(lines, line, _) =
    list.zip(tokens, ends)
    |> list.fold(#([], [], token.Whitespace("")), fn(acc, entry) {
      let #(lines, line, previous) = acc
      let #(#(token, start), end) = entry
      let raw =
        bit_array.slice(bits, start, end - start)
        |> result.try(bit_array.to_string)
        |> result.unwrap("")
      let style = token_style(token, previous)
      let #(lines, line) = case string.split(raw, "\n") {
        [first, ..rest] ->
          list.fold(
            rest,
            #(lines, [span.span_styled(first, style), ..line]),
            fn(acc, part) {
              let #(lines, line) = acc
              #([list.reverse(line), ..lines], [span.span_styled(part, style)])
            },
          )
        [] -> #(lines, line)
      }
      let previous = case token {
        token.Whitespace(_) | token.Comment(_) -> previous
        _ -> token
      }
      #(lines, line, previous)
    })
  list.reverse([list.reverse(line), ..lines])
}

// Names are coloured by what is before them, `!` is a builtin and `@` or `#` a reference.
fn token_style(current: token.Token, previous: token.Token) -> style.Style {
  case current {
    token.UnexpectedGrapheme(_)
    | token.UnterminatedString(_)
    | token.InvalidEscape(_) ->
      style.default_style()
      |> style.add_modifier(style.underline())
      |> style.with_underline_color(style.Rgb(255, 0, 0))
    _ ->
      syntax_style(case current, previous {
        token.Comment(_), _ -> frame.Comment
        token.Name(_), token.Bang -> frame.Builtin
        token.Name(_), token.At | token.Name(_), token.Hash -> frame.Symbol
        token.Name(_), token.Dot -> frame.Plain
        token.Name(_), _ -> frame.Variable
        token.Uppername(_), _ -> frame.ClassName
        token.Integer(_), _ -> frame.Number
        token.String(_), _ -> frame.String
        token.Bang, _ -> frame.Builtin
        token.At, _ | token.Hash, _ -> frame.Symbol
        token.Let, _
        | token.Match, _
        | token.Perform, _
        | token.Deep, _
        | token.Handle, _
        | token.Import, _
        | token.Todo, _
        -> frame.Keyword
        token.Whitespace(_), _ -> frame.Plain
        _, _ -> frame.Punctuation
      })
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
