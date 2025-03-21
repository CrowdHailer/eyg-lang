import eyg/analysis/type_/isomorphic as t
import eyg/ir/tree as ir
import gleam/int
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import morph/analysis
import morph/editable as e
import morph/input
import morph/picker
import website/components/snippet
import website/sync/cache
import website/sync/client

fn empty() {
  new(e.from_annotated(ir.vacant()))
}

fn new(source) {
  let snippet = snippet.init(source)
  let result = snippet.update(snippet, snippet.UserFocusedOnCode)
  #(result, 0)
}

fn command(state, key) {
  let #(#(snippet, action), i) = state
  case action {
    snippet.Nothing | snippet.ReturnToCode | snippet.NewCode -> Nil
    _ ->
      panic as {
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(action)
      }
  }
  #(snippet.update(snippet, snippet.UserPressedCommandKey(key)), i + 1)
}

fn fails_with(state, reason) {
  let #(#(snippet, action), i) = state
  case action {
    snippet.Failed(message) -> should.equal(message, reason)
    _ ->
      panic as {
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(action)
      }
  }
  // increment counter as dismissing error would normally mean a navigation
  #(#(snippet, snippet.Nothing), i + 1)
}

pub fn handle_picker(snippet, check, i) {
  let assert snippet.Snippet(status: snippet.Editing(mode), ..) = snippet
  let suggestions = case mode {
    snippet.Pick(picker:, ..) -> picker.suggestions
    _ ->
      panic as {
        "bad mode at " <> int.to_string(i) <> ": " <> string.inspect(mode)
      }
  }
  let message = case check(suggestions) {
    Ok(value) -> picker.Decided(value)
    Error(Nil) -> picker.Dismissed
  }
  snippet.MessageFromPicker(message)
}

fn pick_from(state, check) {
  let #(#(snippet, action), i) = state
  case action {
    snippet.FocusOnInput -> Nil
    _ ->
      panic as {
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(action)
      }
  }
  let message = handle_picker(snippet, check, i)
  #(snippet.update(snippet, message), i + 1)
}

fn pick(state, value) {
  pick_from(state, fn(_) { Ok(value) })
}

fn enter_integer(state, number) {
  let #(#(snippet, action), i) = state
  case action {
    snippet.FocusOnInput -> Nil
    _ ->
      panic as {
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(action)
      }
  }
  let assert snippet.Snippet(status: snippet.Editing(mode), ..) = snippet
  let Nil = case mode {
    snippet.EditInteger(..) -> Nil
    _ ->
      panic as {
        "bad mode at " <> int.to_string(i) <> ": " <> string.inspect(mode)
      }
  }
  let message =
    snippet.MessageFromInput(input.UpdateInput(int.to_string(number)))
  let #(snippet, _) = snippet.update(snippet, message)
  let message = snippet.MessageFromInput(input.Submit)
  #(snippet.update(snippet, message), i + 1)
}

pub fn enter_text(snippet, text, i) {
  let assert snippet.Snippet(status: snippet.Editing(mode), ..) = snippet
  let Nil = case mode {
    snippet.EditText(..) -> Nil
    _ ->
      panic as {
        "bad mode at " <> int.to_string(i) <> ": " <> string.inspect(mode)
      }
  }
  let message = snippet.MessageFromInput(input.UpdateInput(text))
  let #(snippet, _) = snippet.update(snippet, message)
  let message = snippet.MessageFromInput(input.Submit)
  snippet.update(snippet, message)
}

fn enter_string(state, text) {
  let #(#(snippet, action), i) = state
  case action {
    snippet.FocusOnInput -> Nil
    _ ->
      panic as {
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(action)
      }
  }
  #(enter_text(snippet, text, i), i + 1)
}

fn click(state, path) {
  let #(#(snippet, _action), i) = state
  #(snippet.update(snippet, snippet.UserClickedCode(path)), i + 1)
}

fn analyse(state, effects) {
  let #(client, _) = client.default()
  let #(#(snippet, action), i) = state
  let snippet.Snippet(editable:, ..) = snippet

  let analysis =
    analysis.do_analyse(
      editable,
      analysis.context()
        |> analysis.with_references(cache.type_map(client.cache))
        |> analysis.with_effects(effects),
    )
  let snippet = snippet.Snippet(..snippet, analysis: Some(analysis))
  #(#(snippet, action), i)
}

fn has_code(state, expected) {
  let #(#(snippet, action), i) = state
  case action {
    snippet.ReturnToCode | snippet.NewCode -> Nil
    _ ->
      panic as {
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(action)
      }
  }
  snippet.source(snippet)
  |> should.equal(expected)
  Nil
}

pub fn assigning_to_variable_test() {
  empty()
  |> command("n")
  |> enter_integer(17)
  |> command("e")
  |> pick_from(fn(options) {
    should.equal(options, [])
    Ok("x")
  })
  |> analyse([])
  |> command("v")
  |> pick_from(fn(options) {
    should.equal(options, [#("x", "Integer")])
    Ok("x")
  })
  |> has_code(e.Block([#(e.Bind("x"), e.Integer(17))], e.Variable("x"), True))
}

pub fn assign_above_at_end_of_block_test() {
  new(e.Block(
    [#(e.Bind("x"), e.Integer(5)), #(e.Bind("y"), e.Integer(6))],
    e.Variable("x"),
    True,
  ))
  |> click([2])
  |> command("E")
  |> pick("z")
  |> command("n")
  |> enter_integer(6)
  |> has_code(e.Block(
    [
      #(e.Bind("x"), e.Integer(5)),
      #(e.Bind("y"), e.Integer(6)),
      #(e.Bind("z"), e.Integer(6)),
    ],
    e.Variable("x"),
    True,
  ))
}

pub fn create_record_test() {
  empty()
  |> command("r")
  |> pick("name")
  |> command("s")
  |> enter_string("Evelyn")
  |> has_code(e.Record([#("name", e.String("Evelyn"))], None))
}

pub fn insert_perform_suggestions_test() {
  empty()
  |> analyse([#("Alert", #(t.String, t.unit))])
  |> command("p")
  |> pick_from(fn(options) {
    should.equal(options, [#("Alert", "String : {}")])
    Ok("Alert")
  })
  |> has_code(e.Call(e.Perform("Alert"), [e.Vacant]))
}

pub fn search_for_vacant_failure_test() {
  new(e.Block([#(e.Bind("x"), e.Integer(12))], e.Integer(13), True))
  |> command(" ")
  |> fails_with(snippet.ActionFailed("jump to error"))
}

pub fn search_for_vacant_test() {
  new(e.Block([#(e.Bind("x"), e.Integer(99))], e.Vacant, True))
  |> command(" ")
  |> command("n")
  |> enter_integer(88)
  |> has_code(e.Block([#(e.Bind("x"), e.Integer(99))], e.Integer(88), True))
}
// TODO copy paste should be busy
