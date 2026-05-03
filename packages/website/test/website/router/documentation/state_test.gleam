import eyg/analysis/inference/levels_j/contextual as infer
import eyg/ir/tree as ir
import gleam/dict
import gleam/option.{None}
import morph/editable
import website/harness/browser
import website/routes/documentation/state.{State}
import website/run_test.{cid_from_tree, module_response}

pub fn analyse_web_effect_test() {
  let source = ir.call(ir.perform("Alert"), [ir.string("hi")])
  let assert #(state, []) = with_source(source)
  let assert [] = infer.all_errors(default(state).analysis)
}

pub fn analyse_reference_test() {
  let lib = ir.record([#("count", ir.integer(43))])
  let cid = cid_from_tree(lib)

  let source = ir.get(ir.reference(cid), "count")
  let assert #(state, [effect]) = with_source(source)
  let assert [#([1], reason)] = infer.all_errors(default(state).analysis)
  echo reason
  let assert browser.Fetch(_request, resume:) = effect
  let message = resume(Ok(module_response(lib)))
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

  let #(examples, context, effects) =
    state.init_collection(sources, state.context())

  let mode = state.Navigating(id: "default", failure: None)
  let state = State(mode:, examples:, context: context)
  #(state, effects)
}
