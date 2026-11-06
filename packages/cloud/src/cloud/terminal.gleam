//// The text of the terminal: prompts, input and output as styled lines.
////
//// Everything shown in the terminal is built here as `etui` lines and only
//// turned into HTML at the edge, so the terminal stays a text buffer.

import cloud/code
import cloud/sessions
import cloud/shell.{type Output}
import cloud/terminal/ansi
import etui/span.{type Line}
import etui/style.{type Style}
import gleam/list
import gleam/string
import morph/editable as e

pub const prompt = "> "

pub const indent = "  "

pub fn plain() -> Style {
  style.default_style()
}

pub fn prompt_style() -> Style {
  style.with_fg(plain(), style.Indexed(2))
  |> style.add_modifier(style.bold())
}

pub fn error_style() -> Style {
  style.with_fg(plain(), style.Indexed(1))
}

pub fn info_style() -> Style {
  style.with_fg(plain(), style.Indexed(6))
}

pub fn dim_style() -> Style {
  style.add_modifier(plain(), style.dim())
}

/// Code that was run, after a prompt.
pub fn code_lines(expression: e.Expression) -> List(Line) {
  prompted(code.lines(expression))
}

/// A command from the history, after a prompt.
pub fn command_lines(command: sessions.Command) -> List(Line) {
  case command {
    sessions.Code(source) -> code_lines(source)
  }
}

/// Put the prompt before the first line and indent the rest to match.
pub fn prompted(lines: List(Line)) -> List(Line) {
  list.index_map(lines, fn(line, index) {
    let prefix = case index {
      0 -> span.span_styled(prompt, prompt_style())
      _ -> span.span_plain(indent)
    }
    span.Line(..line, spans: [prefix, ..line.spans])
  })
}

pub fn output_lines(output: Output) -> List(Line) {
  case output {
    shell.Stdout(text) -> ansi.parse(text, plain())
    shell.Stderr(text) -> ansi.parse(text, error_style())
    shell.Result(text) -> ansi.parse(text, plain())
    shell.Failure(text) -> ansi.parse(text, error_style())
    shell.Hint(text) -> ansi.parse(text, dim_style())
  }
}

/// Plain text of lines, for tests and logs.
pub fn to_text(lines: List(Line)) -> String {
  list.map(lines, fn(line) {
    list.map(line.spans, fn(s) { s.content }) |> string.concat
  })
  |> string.join("\n")
}
