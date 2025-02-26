import eyg/analysis/type_/isomorphic as t
import eyg/interpreter/value as v
import gleam/dict
import gleam/io
import gleam/option.{None}
import gleeunit/should
import morph/editable as e
import website/components/reload
import website/sync/cache

fn new(editable) {
  let source = e.to_annotated(editable, [])
  reload.init(cache.init(), source)
}

fn click_app(state) {
  reload.update(state, reload.UserClickedApp)
}

fn set_source(state, editable) {
  let source = e.to_annotated(editable, [])
  reload.update(state, reload.ParentUpdatedSource(source))
}

pub fn init_with_app_starts_value_test() {
  let state = new(counter_app())
  state.type_errors
  |> should.equal([])
  state.value
  |> should.be_some()
  |> should.equal(v.Integer(0))

  let state = click_app(state)
  state.value
  |> should.be_some()
  |> should.equal(v.Integer(1))
}

pub fn add_app_after_init_test() {
  let state = new(e.Vacant)
  state.value
  |> should.be_none()
  let state = set_source(state, counter_app())
  todo as "tes"
}

// updating with source doesnt tigger immediatly

pub fn valid_source_without_init_fails_test() {
  let source = e.Record([#("foo", e.Integer(10))], None)
  let state = new(source)
  state.type_errors
  |> should.equal([#([], "missing row 'init'")])
}

pub fn incomplete_source_shows_error_test() {
  let source = e.Vacant
  let current_state = t.Integer
  let refs = dict.new()
  reload.check_against_state(source, current_state, refs)
  |> should.be_error()
  |> should.equal([#([], "code incomplete")])
}

pub fn program_with_inconsistent_types_test() {
  let source = e.Call(e.Integer(99), [e.Record([], None)])
  let current_state = t.Integer
  let refs = dict.new()
  reload.check_against_state(source, current_state, refs)
  |> should.be_error()
  |> should.equal([
    #([], "type missmatch given: Integer expected: ({} <..1>) -> 0"),
  ])
}

pub fn source_with_same_init_needs_handle_render_test() {
  let source = e.Record([#("init", e.Integer(10))], None)
  let current_state = t.Integer
  let refs = dict.new()
  reload.check_against_state(source, current_state, refs)
  |> should.be_error()
  |> should.equal([#([], "missing row 'handle'")])
}

// examples

fn counter_app() {
  e.Record(
    [
      #("init", e.Integer(0)),
      #(
        "handle",
        e.Function(
          [e.Bind("state"), e.Bind("message")],
          e.Call(e.Builtin("int_add"), [e.Variable("state"), e.Integer(1)]),
        ),
      ),
      #(
        "render",
        e.Function(
          [e.Bind("state")],
          e.Call(e.Builtin("int_to_string"), [e.Variable("state")]),
        ),
      ),
    ],
    None,
  )
}
