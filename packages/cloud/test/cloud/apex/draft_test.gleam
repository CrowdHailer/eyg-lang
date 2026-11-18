import cloud/apex/draft
import cloud/helpers
import cloud/sessions/turn
import etui/span
import etui/style
import gleam/list
import gleam/string
import morph/terminal/textarea

fn type_(draft, keys) {
  let state = helpers.state()
  list.fold(keys, draft, fn(draft, key) {
    let assert #(draft.Edited(draft), _) = draft.key(draft, key, state, [])
    draft
  })
}

fn send(draft) {
  let assert #(draft.Send(input, draft), _) =
    draft.key(draft, "enter", helpers.state(), [])
  #(input, draft)
}

pub fn multiline_message_test() {
  let typed =
    type_(draft.message(), ["h", "i", "shift+enter", "y", "o", "backspace", "u"])
  let #(input, rest) = send(typed)
  assert input == turn.Message("hi\nyu")
  assert rest == draft.message()
  // Nothing is sent without text, escape is left to the interface.
  let assert #(draft.Unhandled, _) =
    draft.key(draft.message(), "enter", helpers.state(), [])
  let assert #(draft.Unhandled, _) =
    draft.key(draft.message(), "esc", helpers.state(), [])
}

pub fn switch_between_text_and_structure_test() {
  // A number in the structural editor, then text.
  let program = type_(draft.program(), ["n", "4", "enter"])
  let program = type_(program, ["tab", ..string.to_graphemes("!int_add(1, 2)")])
  assert "text" == draft.mode(program)
  // Switching back keeps both drafts.
  let program = type_(program, ["tab"])
  assert "structured" == draft.mode(program)
  let assert draft.Program(text:, ..) = program
  assert "!int_add(1, 2)" == textarea.value(text)
  let assert #(turn.Program(_), program) = send(program)
  let #(input, _) = send(type_(program, ["tab"]))
  assert input == turn.Code("!int_add(1, 2)")
}

pub fn paste_text_test() {
  let state = helpers.state()
  let assert #(draft.Edited(message), _) =
    draft.paste(draft.message(), "line one\r\nline two", state)
  let assert draft.Message(text) = message
  assert "line one\nline two" == textarea.value(text)

  // Pasted into the structural editor, text replaces the expression in focus.
  let assert #(draft.Edited(program), _) =
    draft.paste(draft.program(), "!int_add(1, 2)", state)
  let assert #(draft.Send(turn.Program(_), _), _) =
    draft.key(program, "enter", state, [])
  let assert #(draft.Problem(_), _) =
    draft.paste(draft.program(), "let x =", state)
}

pub fn edit_within_text_test() {
  // Correct the first argument after typing the whole call.
  let program =
    type_(draft.program(), ["tab", ..string.to_graphemes("!int_add(3, 2)")])
  let program =
    type_(program, ["ctrl+left", "ctrl+left", "delete", "1", "end", "home"])
  let #(input, _) = send(program)
  assert input == turn.Code("!int_add(1, 2)")

  // Program text is highlighted, a message is not.
  let assert #(lines, 0) = draft.lines(program, False, 40)
  let assert [line] = lines
  // The bang and the name are both coloured as a builtin.
  let assert [builtin, ..] = line.spans
  assert builtin.content == "!int_add"
  assert builtin.style != style.default_style()
  let message = type_(draft.message(), string.to_graphemes("!int_add(1, 2)"))
  let assert #([line], 0) = draft.lines(message, False, 40)
  assert [span.span_plain("!int_add(1, 2)")] == line.spans
}
