import eyg/analysis/type_/isomorphic as t
import gleam/int
import gleam/io
import gleam/list
import gleam/string
import gleeunit/should
import morph/editable as e
import morph/input
import morph/projection
import website/components/shell.{Shell}
import website/components/snippet
import website/components/snippet_test
import website/sync/client

fn new(effects) {
  let #(client, _) = client.default()
  let shell = shell.init(effects, client.cache)
  // let result = snippet.update(snippet, snippet.UserFocusedOnCode)
  #(#(shell, shell.Nothing), 0)
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
  assert_action(action, [shell.Nothing], i)
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
  // This handles 2 messages we want both to go through the update path so don't share with snippet
  let #(#(shell, action), i) = state
  let Shell(source: snippet, ..) = shell
  let assert snippet.Snippet(status: snippet.Editing(mode), ..) = snippet
  let Nil = case mode {
    snippet.EditText(..) -> Nil
    _ ->
      panic as {
        "bad mode at " <> int.to_string(i) <> ": " <> string.inspect(mode)
      }
  }
  let message = snippet.MessageFromInput(input.UpdateInput(text))
  let #(shell, _) = shell.update(shell, message)
  let message = snippet.MessageFromInput(input.Submit)
  #(shell.update(shell, message), i + 1)
}

fn handle_effect(state, label) {
  let #(#(shell, action), i) = state
  case action {
    shell.RunEffect(value, blocking) -> {
      io.debug(blocking == label)
    }
    got -> {
      let message =
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(got)
      panic as message
    }
  }
  todo as "effect"
}

fn has_executed(state, with) {
  let #(#(shell, action), i) = state
  let Shell(previous:, ..) = shell
  case list.first(previous) {
    Ok(shell.Executed(_, _, recent)) -> {
      recent.source
      |> should.equal(with)
      state
    }
    Error(Nil) ->
      panic as { "no previous history after step " <> int.to_string(i) }
  }
}

// typing is automatic
// errors are shown

pub fn types_remain_in_scope_test() {
  new([])
  |> command("e")
  |> pick("count")
  |> command("s")
  |> enter_text("Shelly")
  |> command("Enter")
  |> has_executed(e.Block(
    [#(e.Bind("count"), e.String("Shelly"))],
    e.Vacant,
    True,
  ))
  |> command("v")
  |> pick_from(fn(options) {
    should.equal(options, [#("count", "String")])
    Ok("count")
  })
  |> command("e")
  |> pick("var2")
  |> command("Enter")
  |> has_executed(e.Block(
    [#(e.Bind("var2"), e.Variable("count"))],
    e.Vacant,
    True,
  ))
  |> command("v")
  |> pick_from(fn(options) {
    should.equal(options, [#("var2", "String"), #("count", "String")])
    Error(Nil)
  })
}

// Everything is passed in by events so that nested mvu works
// Just call it run effect
pub fn effects_are_recorded_test() {
  let inner = fn(_) { todo }
  new([
    #("Inner", #(t.String, t.Integer, inner)),
    #("Outer", #(t.Integer, t.unit, fn(_) { todo })),
  ])
  |> command("p")
  |> pick_from(fn(options) {
    should.equal(options, [
      #("Inner", "String : Integer"),
      #("Outer", "Integer : {}"),
    ])
    Ok("Outer")
  })
  |> command("p")
  |> pick_from(fn(_options) { Ok("Inner") })
  |> command("s")
  |> enter_text("Bulb")
  |> command("Enter")
  |> handle_effect(inner)
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

// A runner keeps the ID but it needs composing with the scope to types and other new versions below
// The view history function can be a state of the shell
