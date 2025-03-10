import eyg/analysis/type_/binding/error
import eyg/interpreter/value as v
import eyg/ir/dag_json
import gleam/bit_array
import gleam/option.{None, Some}
import gleeunit/should
import morph/editable as e
import website/components/reload
import website/sync/cache

fn new(source) {
  reload.init(cache.init(), source)
}

fn click_app(state) {
  reload.update(state, reload.UserClickedApp)
}

fn click_migrate(state) {
  reload.update(state, reload.UserClickedMigrate)
}

fn set_source(state, source) {
  reload.update(state, reload.ParentUpdatedSource(source))
}

pub fn init_with_app_starts_value_test() {
  let state = new(counter_app())
  state.type_errors
  |> should.equal([])
  state.value
  |> should.be_some()
  |> should.equal(v.Integer(10))

  let state = click_app(state)
  state.value
  |> should.be_some()
  |> should.equal(v.Integer(11))
}

pub fn add_app_after_init_test() {
  let state = new(e.Integer(1) |> e.to_annotated([]))
  state.value
  |> should.be_none()
  let state = set_source(state, counter_app())
  state.type_errors
  |> should.equal([])

  state.value
  |> should.be_none()
  let state = click_migrate(state)
  state.value
  |> should.be_some()
  |> should.equal(v.Integer(10))
}

// updating with source doesnt tigger immediatly

pub fn incomplete_source_shows_error_test() {
  let source = e.Vacant
  let state = new(source |> e.to_annotated([]))
  state.type_errors
  |> should.equal([#([], error.Todo)])
}

pub fn valid_source_without_init_fails_test() {
  let source = e.Record([#("foo", e.Integer(10))], None)
  let state = new(source |> e.to_annotated([]))
  state.type_errors
  |> should.equal([#([], error.MissingRow("init"))])
}

pub fn source_with_same_init_needs_handle_render_test() {
  let source = e.Record([#("init", e.Integer(10))], None)
  let state = new(source |> e.to_annotated([]))
  state.type_errors
  |> should.equal([#([], error.MissingRow("handle"))])
}

pub fn program_with_inconsistent_types_test() {
  let source = e.Record([#("init", e.String("hi"))], None)
  let state = new(source |> e.to_annotated([]))

  // Force state to have evaluated
  let state = reload.State(..state, value: Some(v.String("hi")))
  state.value
  |> should.be_some()
  |> should.equal(v.String("hi"))

  let state = set_source(state, counter_app())
  state.type_errors
  |> should.equal([#([], error.MissingRow("migrate"))])
}

// examples

fn counter_app() {
  "{\"0\":\"l\",\"l\":\"initial\",\"t\":{\"0\":\"l\",\"l\":\"handle\",\"t\":{\"0\":\"l\",\"l\":\"render\",\"t\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"a\",\"a\":{\"0\":\"u\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"initial\"},\"f\":{\"0\":\"e\",\"l\":\"init\"}}},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"handle\"},\"f\":{\"0\":\"e\",\"l\":\"handle\"}}},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"render\"},\"f\":{\"0\":\"e\",\"l\":\"render\"}}},\"v\":{\"0\":\"f\",\"b\":{\"0\":\"l\",\"l\":\"count\",\"t\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"count\"},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"s\",\"v\":\"the total is \"},\"f\":{\"0\":\"b\",\"l\":\"string_append\"}}},\"v\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"count\"},\"f\":{\"0\":\"b\",\"l\":\"int_to_string\"}}},\"l\":\"count\"}},\"v\":{\"0\":\"f\",\"b\":{\"0\":\"f\",\"b\":{\"0\":\"a\",\"a\":{\"0\":\"i\",\"v\":1},\"f\":{\"0\":\"a\",\"a\":{\"0\":\"v\",\"l\":\"state\"},\"f\":{\"0\":\"b\",\"l\":\"int_add\"}}},\"l\":\"message\"},\"l\":\"state\"}},\"v\":{\"0\":\"i\",\"v\":10}}"
  |> bit_array.from_string
  |> dag_json.from_block
  |> should.be_ok
  |> e.from_annotated
  |> e.to_annotated([])
}
