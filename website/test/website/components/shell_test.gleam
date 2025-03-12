import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleeunit/should
import website/components/shell
import website/components/snippet
import website/components/snippet_test
import website/sync/client

fn new(effects) {
  let #(client, _) = client.default()
  let shell = shell.init(effects, client.cache)
  // let result = snippet.update(snippet, snippet.UserFocusedOnCode)
  #(#(shell, snippet.Nothing), 0)
}

fn assert_action(got, expected, i) {
  case list.contains(expected, got) {
    True -> Nil
    False -> {
      let message =
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(got)
      panic as message
    }
  }
}

fn command(state, key) {
  let #(#(shell, action), i) = state
  // assert_action(action, [snippet.Nothing, snippet.FocusOnCode], i)
  #(shell.update(shell, snippet.UserPressedCommandKey(key)), i + 1)
}

fn pick_from(state, check) {
  let #(#(shell, action), i) = state
  // assert_action(action, [snippet.FocusOnInput], i)
  let shell.Shell(source:, ..) = shell
  let message = snippet_test.handle_picker(source, check, i)
  #(shell.update(shell, message), i + 1)
}

fn pick(state, value) {
  pick_from(state, fn(_) { Ok(value) })
}

fn enter_text(state, text) {
  let #(#(shell, action), i) = state
  let shell.Shell(source:, ..) = shell
  let message = snippet_test.enter_text(source, text, i)
  #(shell.update(shell, message), i + 1)
}

pub fn types_remain_in_scope_test() {
  new([])
  |> command("e")
  |> pick("count")
  |> command("s")
  |> enter_text("Shelly")
  |> command("Enter")
  // completes immediatly
  |> command("v")
  |> pick_from(fn(options) {
    should.equal(options, [#("v", "")])
    Error(Nil)
  })
  |> io.debug

  todo as "test"
}
// Test task only starts once
// needs equal for type narrow test
// needs effects for perform test
// When is cancelled or task fails state needs to update
// error if missing ref
// test incremental building of scope
// context should take cache
// Test will resume from missing ref
