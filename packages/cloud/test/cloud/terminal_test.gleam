import cloud/shell
import cloud/terminal
import etui/span

pub fn command_lines_test() {
  let assert Ok(source) = shell.parse("let x = 1\nx")
  assert terminal.to_text(terminal.code_lines(source)) == "> let x = 1\n  x"
}

pub fn output_lines_test() {
  let assert [line] = terminal.output_lines(shell.Failure("boom"))
  let assert [span.Span(content: "boom", style:, ..)] = line.spans
  assert style == terminal.error_style()
}

pub fn hint_lines_are_dim_test() {
  let assert [line] = terminal.output_lines(shell.Hint("try this"))
  let assert [span.Span(style:, ..)] = line.spans
  assert style == terminal.dim_style()
}
