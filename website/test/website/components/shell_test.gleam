import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/http
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import morph/editable as e
import morph/input
import multiformats/cid/v1
import spotless/origin
import website/components/runner
import website/components/shell.{CurrentMessage, Shell}
import website/components/snippet
import website/components/snippet_test
import website/sync/cache
import website/sync/client
import website/sync/protocol

fn new(effects) {
  let #(client, _) =
    client.init(origin.Origin(http.Https, "registry.eyg.test", None))
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

fn update_cache(state, cache) {
  let #(#(shell, _action), i) = state
  #(shell.update(shell, shell.CacheUpdate(cache)), i + 1)
}

fn command(state, key) {
  let #(#(shell, action), i) = state
  assert_action(action, [shell.Nothing, shell.FocusOnCode], i)
  #(
    shell.update(shell, CurrentMessage(snippet.UserPressedCommandKey(key))),
    i + 1,
  )
}

fn pick_from(state, check) {
  let #(#(shell, _action), i) = state
  // assert_action(action, [snippet.FocusOnInput], i)
  let shell.Shell(source:, ..) = shell
  let message = snippet_test.handle_picker(source, check, i)
  #(shell.update(shell, CurrentMessage(message)), i + 1)
}

fn pick(state, value) {
  pick_from(state, fn(_) { Ok(value) })
}

fn enter_text(state, text) {
  // This handles 2 messages we want both to go through the update path so don't share with snippet
  let #(#(shell, _action), i) = state
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
  let #(shell, _) = shell.update(shell, CurrentMessage(message))
  let message = snippet.MessageFromInput(input.Submit)
  #(shell.update(shell, CurrentMessage(message)), i + 1)
}

fn click_previous(state, index) {
  let #(#(shell, _action), i) = state
  #(shell.update(shell, shell.UserClickedPrevious(index)), i + 1)
}

fn has_action(state, expected) {
  let #(#(_shell, action), i) = state
  case action == expected {
    True -> Nil
    False ->
      panic as {
        "unexpected at " <> int.to_string(i) <> ": " <> string.inspect(action)
      }
  }
  state
}

// sync to keep the pipeline running
fn run_effect(state, sync) {
  let #(#(shell, action), i) = state
  case action {
    shell.RunExternalHandler(ref, _blocking) -> {
      let message = shell.RunnerMessage(runner.HandlerCompleted(ref, sync(Nil)))
      #(shell.update(shell, message), i + 1)
    }
    got -> {
      let message =
        "bad action at " <> int.to_string(i) <> ": " <> string.inspect(got)
      panic as message
    }
  }
}

fn has_executed(state, with) {
  let #(#(shell, _action), i) = state
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

fn has_value(state, expected) {
  let #(#(shell, _action), i) = state
  let Shell(previous:, ..) = shell
  case list.first(previous) {
    Ok(shell.Executed(value, _effects, _recent)) -> {
      value
      |> should.equal(Some(expected))
      state
    }
    Error(Nil) ->
      panic as { "no previous history after step " <> int.to_string(i) }
  }
}

fn has_effects(state, expected) {
  let #(#(shell, _action), i) = state
  let Shell(previous:, ..) = shell
  case list.first(previous) {
    Ok(shell.Executed(_, effects, _recent)) -> {
      effects
      |> should.equal(expected)
      state
    }
    Error(Nil) ->
      panic as { "no previous history after step " <> int.to_string(i) }
  }
}

fn has_input(state, expected) {
  let #(#(shell, _action), _i) = state
  let Shell(source:, ..) = shell
  source.editable
  |> should.equal(expected)
  state
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
pub fn effects_are_recorded_test() {
  new([
    #(
      "Inner",
      #(#(t.String, t.Integer), fn(_) { Ok(fn() { panic as "test handler" }) }),
    ),
    #(
      "Outer",
      #(#(t.Integer, t.unit), fn(_) { Ok(fn() { panic as "test handler" }) }),
    ),
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
  |> run_effect(fn(_v) {
    // TODO how do we get v
    // should.equal(v, v.String("Bulb"))
    v.Integer(101)
  })
  |> run_effect(fn(_v) {
    // TODO how do we get v

    // should.equal(v, v.Integer(101))
    v.unit()
  })
  |> has_effects([
    #("Outer", #(v.Integer(101), v.unit())),
    #("Inner", #(v.String("Bulb"), v.Integer(101))),
  ])
  |> has_input(e.Vacant)
}

// Test task only starts once
pub fn run_only_starts_once_test() {
  new([
    #(
      "Foo",
      #(#(t.String, t.Integer), fn(_) { Ok(fn() { panic as "test handler" }) }),
    ),
  ])
  |> command("p")
  |> pick_from(fn(_options) { Ok("Foo") })
  |> command("s")
  |> enter_text("Go Go")
  |> command("Enter")
  |> fn(state) {
    let #(#(shell, _action), i) = state
    #(#(shell, shell.Nothing), i)
  }
  |> command("Enter")
  |> has_action(shell.Nothing)
}

pub fn foo_src() {
  ir.record([#("foo", ir.string("My value"))])
}

pub fn foo_cid() {
  let encoded = "baguqeera5ot4b6mgodu27ckwty7eyr25lsqjke44drztct4w7cwvs77vkmca"
  let assert Ok(#(cid, _)) = v1.from_string(encoded)
  cid
}

fn cache() -> cache.Cache {
  cache.init()
  |> cache.add(foo_cid(), dag_json.to_block(foo_src()))
  |> cache.apply(protocol.ReleasePublished("foo", 1, foo_cid()))
}

pub fn run_a_reference_test() {
  new([])
  |> update_cache(cache())
  |> command("#")
  |> pick_from(fn(options) {
    should.equal(options, [])
    Ok(foo_cid() |> v1.to_string)
  })
  |> command("g")
  |> pick_from(fn(options) {
    should.equal(options, [#("foo", "String")])
    Ok("foo")
  })
  |> command("Enter")
  |> has_value(v.String("My value"))
  |> has_input(e.Vacant)
}

pub fn run_a_late_reference_test() {
  new([])
  |> command("#")
  |> pick_from(fn(options) {
    should.equal(options, [])
    Ok(foo_cid() |> v1.to_string)
  })
  |> command("g")
  |> pick_from(fn(options) {
    should.equal(options, [])
    Ok("foo")
  })
  |> command("Enter")
  |> update_cache(cache())
  |> has_value(v.String("My value"))
  |> has_input(e.Vacant)
}

pub fn moving_above_loads_last_expression_test() {
  new([])
  |> command("s")
  |> enter_text("Banjo")
  |> command("Enter")
  |> has_input(e.Vacant)
  |> command("ArrowUp")
  |> has_input(e.String("Banjo"))
}

pub fn user_clicking_previous_test() {
  new([])
  |> command("s")
  |> enter_text("Pebble")
  |> command("Enter")
  |> has_input(e.Vacant)
  |> click_previous(0)
  |> has_input(e.String("Pebble"))
}

pub fn user_can_copy_from_input_test() {
  new([])
  |> command("s")
  |> enter_text("Jack")
  |> command("y")
  |> fn(state) {
    let #(#(shell, action), i) = state
    action
    |> should.equal(shell.WriteToClipboard("{\"0\":\"s\",\"v\":\"Jack\"}"))
    #(
      shell.update(
        shell,
        CurrentMessage(snippet.ClipboardWriteCompleted(Ok(Nil))),
      ),
      i,
    )
  }
}

pub fn user_can_paste_to_input_test() {
  new([])
  |> command("Y")
  |> fn(state) {
    let #(#(shell, action), i) = state
    action
    |> should.equal(shell.ReadFromClipboard)
    #(
      shell.update(
        shell,
        CurrentMessage(
          snippet.ClipboardReadCompleted(Ok("{\"0\":\"s\",\"v\":\"Farm\"}")),
        ),
      ),
      i,
    )
  }
  |> has_input(e.String("Farm"))
}
