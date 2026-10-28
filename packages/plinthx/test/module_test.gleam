import gleam/javascript/promise
import plinthx/javascript/foreign
import plinthx/javascript/module

pub fn native_dynamic_import_resolves_exports_and_reports_failures_test() {
  use loaded <- promise.await(module.load(module.url()))
  let assert Ok(loaded) = loaded
  assert foreign.has_own(loaded, "url")
  assert foreign.is_function(foreign.property(loaded, "load"))
  use missing <- promise.map(module.load("./this-module-does-not-exist.mjs"))
  let assert Error(_) = missing
}
