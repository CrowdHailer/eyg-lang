import cloud/apex/draft
import cloud/helpers
import cloud/sessions/turn
import gleam/list
import gleam/string

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
  let assert draft.Program(text: "!int_add(1, 2)", ..) = program
  let assert #(turn.Program(_), program) = send(program)
  let #(input, _) = send(type_(program, ["tab"]))
  assert input == turn.Code("!int_add(1, 2)")
}

pub fn paste_text_test() {
  let state = helpers.state()
  let assert #(draft.Edited(message), _) =
    draft.paste(draft.message(), "line one\r\nline two", state)
  assert message == draft.Message("line one\nline two")

  // Pasted into the structural editor, text replaces the expression in focus.
  let assert #(draft.Edited(program), _) =
    draft.paste(draft.program(), "!int_add(1, 2)", state)
  let assert #(draft.Send(turn.Program(_), _), _) =
    draft.key(program, "enter", state, [])
  let assert #(draft.Problem(_), _) =
    draft.paste(draft.program(), "let x =", state)
}
