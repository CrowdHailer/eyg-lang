import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/error
import eyg/hub/cache
import eyg/ir/cid
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/crypto
import gleam/dict
import gleam/http/response
import gleam/option.{None}
import morph/editable
import morph/picker
import multiformats/cid/v1
import ogre/origin
import pal/system
import website/manipulation
import website/routes/documentation/state.{State}

pub fn analyse_web_effect_test() {
  let source = ir.call(ir.perform("Alert"), [ir.string("hi")])
  let state = with_source(source)
  let assert [] = infer.all_errors(default(state).analysis)
}

pub fn analyse_reference_test() {
  let lib = ir.record([#("count", ir.integer(43))])
  let cid = cid_from_tree(lib)

  let source = ir.get(ir.reference(cid), "count")
  let state = with_source(source)
  let assert [#([1], reason)] = infer.all_errors(default(state).analysis)
  assert error.MissingReference(cid) == reason
  let assert #(_context, [_pull, effect]) =
    state.flush_cache(state.cache, origin.https("eyg.test"))
  let assert system.Fetch(_request, resume:) = effect
  let assert system.Done(message) = resume(Ok(module_response(lib)))
  let #(state, _effects) = state.update(state, message)

  let assert [] = infer.all_errors(default(state).analysis)
}

pub fn insert_reference_test() {
  let lib = ir.record([#("user", ir.string("Bill"))])
  let cid = cid_from_tree(lib)

  let state = with_source(ir.vacant())
  let assert [#([], reason)] = infer.all_errors(default(state).analysis)
  assert error.Todo == reason
  let assert #(state, []) = state.update(state, state.UserPressedKey("#"))
  let assert state.Manipulating(input: manipulation.PickCid(..), ..) =
    state.mode
  let message = state.PickerMessage(picker.Decided(v1.to_string(cid)))
  let assert #(state, [_pull, effect]) = state.update(state, message)
  let assert [#([], reason)] = infer.all_errors(default(state).analysis)
  assert error.MissingReference(cid) == reason
  let assert system.Fetch(_request, resume:) = effect
  let assert system.Done(message) = resume(Ok(module_response(lib)))
  let assert #(state, []) = state.update(state, message)
  let assert [] = infer.all_errors(default(state).analysis)
}

fn default(state) {
  let State(examples:, ..) = state
  let assert Ok(buffer) = dict.get(examples, "default")
  buffer
}

fn with_source(source) {
  let sources = [#("default", editable.from_annotated(source))]

  let #(examples, cache) = state.init_collection(sources, cache.ready())

  let mode = state.Navigating(id: "default", failure: None)
  let state =
    State(
      mode:,
      examples:,
      origin: origin.https("eyg.test"),
      cache: cache,
      counter: 0,
      spotless_origin: origin.https("spotless.test"),
      tokens: dict.new(),
    )
  state
}

fn module_response(source) {
  let body = dag_json.to_block(source)
  response.new(200)
  |> response.set_body(body)
}

pub fn cid_from_tree(source) {
  let cid.Sha256(bytes:, resume:) = cid.from_tree(source)
  resume(crypto.hash(crypto.Sha256, bytes))
}
