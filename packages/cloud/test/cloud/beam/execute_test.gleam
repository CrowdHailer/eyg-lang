import cloud/beam/execute
import cloud/config
import cloud/file_system
import cloud/server
import eyg/hub/cache
import eyg/interpreter/evaluation
import eyg/interpreter/expression
import eyg/ir/tree as ir
import gleam/dict
import gleam/erlang/process
import gleam/result
import gleam/string
import ogre/origin
import touch_grass/source

fn state() {
  let assert Ok(bucket) = config.bucket()
  execute.State(
    origin: origin.https("eyg.test"),
    cache: cache.ready(),
    secrets: dict.new(),
    bucket:,
    pins: dict.new(),
  )
}

// Code is checked with the effects the policy offers, before it runs.
pub fn an_empty_policy_offers_no_effects_test() {
  let state = state()
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let assert #(Error(reason), _, _, []) =
    execute.run("perform Random(10)", state, dict.new(), root, fn(_) { Nil })
  assert "missing row 'Random'" == reason
}

pub fn a_pure_evaluation_names_the_effect_it_refuses_test() {
  let assert Ok(source) = source.parse("perform Random(10)", source.Inline)
  let assert #(Error(reason), _) =
    evaluation.await(expression.execute(source, []))
    |> evaluation.map(result.map_error(_, execute.describe_debug))
    |> execute.pure(state())
  assert "unhandled effect Random({})" == reason
}

pub fn checking_pins_the_packages_code_refers_to_test() {
  let server = server.start(process.new_subject())
  let state =
    execute.State(
      ..state(),
      origin: server.origin(server),
      cache: server.release(cache.empty(), "lib", "1"),
    )
  let assert Ok(root) = execute.files(file_system.empty(), state)
  let assert #(Ok("[1, 1]"), state, _, _) =
    execute.run("[@lib, @lib]", state, dict.new(), root, fn(_) { Nil })
  let assert Ok(_) = dict.get(state.pins, ir.Package("lib"))
}

pub fn a_package_that_was_not_pinned_is_refused_test() {
  let state =
    execute.State(..state(), cache: server.release(cache.empty(), "lib", "1"))
  let assert #(Error(reason), _) =
    execute.lookup_value(ir.Package("lib"), state)
  assert string.ends_with(reason, "not pinned")
}
