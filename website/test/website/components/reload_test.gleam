import eyg/analysis/type_/isomorphic as t
import gleam/dict
import gleam/option.{None}
import gleeunit/should
import morph/editable as e
import website/components/reload

pub fn source_with_vacant_doesnt_check_test() {
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

pub fn source_without_init_fails_test() {
  let source = e.Record([#("foo", e.Integer(10))], None)
  let current_state = t.Integer
  let refs = dict.new()
  reload.check_against_state(source, current_state, refs)
  |> should.be_error()
  |> should.equal([#([], "missing row 'init'")])
}

pub fn source_with_same_init_needs_handle_render_test() {
  let source = e.Record([#("init", e.Integer(10))], None)
  let current_state = t.Integer
  let refs = dict.new()
  reload.check_against_state(source, current_state, refs)
  |> should.be_error()
  |> should.equal([#([], "missing row 'handle'")])
}
