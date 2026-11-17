import etui/span
import gleam/list
import gleam/string
import morph/buffer
import morph/lustre/render
import morph/manipulation as m
import morph/terminal

fn text(lines: List(span.Line)) {
  list.map(lines, fn(line) {
    list.map(line.spans, fn(span) { span.content }) |> string.concat
  })
}

pub fn edit_and_render_code_test() {
  let buffer = buffer.empty()
  let assert Ok(terminal.Edit(m.Operation(apply:, ..))) =
    terminal.binding("n", [], [])
  let assert Ok(m.UserInput(m.EnterInteger(_, rebuild))) = apply(buffer)
  let buffer = rebuild(42)
  assert ["42"]
    == render.projection(buffer.projection, render.Statements, [])
    |> terminal.lines(True)
    |> text
  let assert Ok(terminal.Move(..)) = terminal.binding("right", [], [])
  assert Error(Nil) == terminal.binding("ctrl+q", [], [])
}
