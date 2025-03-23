import eyg/interpreter/break
import eyg/interpreter/value as v
import gleam/dict
import gleam/list
import gleeunit/should
import morph/input
import morph/picker
import website/components/shell
import website/components/snippet
import website/routes/editor

fn update_pad(state, message) {
  editor.update(state, editor.SnippetMessage(message))
}

fn edit_shell(state, message) {
  editor.update(state, editor.ShellMessage(shell.CurrentMessage(message)))
}

// errors are analysed

pub fn scratchpad_state_is_available_in_shell_test() {
  let #(state, _) = editor.init(Nil)

  // select the whole scratchpad
  let #(state, _) = update_pad(state, snippet.UserFocusedOnCode)
  let #(state, _) = update_pad(state, snippet.UserClickedPath([]))
  let #(state, _) = update_pad(state, snippet.UserPressedCommandKey("s"))

  let #(state, _) =
    update_pad(state, snippet.MessageFromInput(input.UpdateInput("wizard")))
  let #(state, _) = update_pad(state, snippet.MessageFromInput(input.Submit))

  let #(state, _) = edit_shell(state, snippet.UserFocusedOnCode)
  let #(state, _) = edit_shell(state, snippet.UserPressedCommandKey("p"))

  let picker = case state.shell.source.status {
    snippet.Editing(snippet.Pick(picker, _rebuild)) -> picker
    _ -> panic as "shell should be in pick mode"
  }

  let suggestions = picker.suggestions
  let effect =
    list.key_find(suggestions, "Import")
    |> should.be_ok
  effect
  // I'd be happy if the picker migrated to an unstringly state model
  |> should.equal("{} : String")

  let #(state, _) =
    edit_shell(state, snippet.MessageFromPicker(picker.Decided("Import")))
  let #(state, _) = edit_shell(state, snippet.UserPressedCommandKey("R"))
  let #(state, _) = edit_shell(state, snippet.UserPressedCommandKey("Enter"))

  let #(reason, _, _, _) =
    state.shell.runner.return
    |> should.be_error
  let empty = dict.new()
  case reason {
    break.UnhandledEffect("Import", v.Record(d)) if d == empty -> Nil
    _ -> panic as "shell should be handling import effect"
  }
  // Need an ability to run the effect.
  // The effect could be a midas thing as that would allow us to check that the value was sync available
  //  but that doesn't work with focusing on inputs etc
}
