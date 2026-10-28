//// Evaluate local modules, such as suites of tasks.
////
//// Modules are pure, references to other modules are resolved from the
//// module's own imports and the packages of a hub fixture.

import eyg/interpreter/break
import eyg/interpreter/expression
import eyg/interpreter/simple_debug
import eyg/interpreter/state as istate
import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/dict
import gleam/json
import gleam/list
import gleam/result
import multiformats/cid/v1
import overlay/eval/fixture/hub.{type Hub}
import overlay/eval/module.{type Loaded}
import overlay/web/tools

pub type Value =
  istate.Value(tools.Meta)

/// The value of a loaded module.
pub fn module(loaded: Loaded, hub: Hub) -> Result(Value, String) {
  let blocks = dict.merge(hub.blocks, loaded.blocks)
  block(loaded.cid, blocks, hub)
}

fn block(cid, blocks, hub) {
  use block <- result.try(
    dict.get(blocks, v1.to_string(cid))
    |> result.replace_error("no module " <> v1.to_string(cid)),
  )
  use source <- result.try(
    json.parse_bits(block, dag_json.decoder(Nil))
    |> result.replace_error("module " <> v1.to_string(cid) <> " is not valid"),
  )
  let source = ir.map_annotation(source, fn(_) { [] })
  loop(expression.execute(source, []), blocks, hub)
}

fn loop(return, blocks, hub: Hub) -> Result(Value, String) {
  case return {
    Ok(value) -> Ok(value)
    Error(#(break.UndefinedReference(reference), _meta, env, k)) -> {
      let cid = case reference {
        ir.Content(cid:) -> Ok(cid)
        ir.Package(package:) -> latest(hub, package)
        ir.Version(package:, version:) -> release(hub, package, version)
        ir.Pinned(release: ir.Release(package:, version:, module:)) ->
          case release(hub, package, version) {
            Ok(cid) if cid == module -> Ok(cid)
            _ -> Error(Nil)
          }
        ir.Relative(..) -> Error(Nil)
      }
      case cid {
        Ok(cid) -> {
          use value <- result.try(block(cid, blocks, hub))
          loop(expression.resume(value, env, k), blocks, hub)
        }
        Error(Nil) ->
          Error("unable to resolve " <> ir.reference_to_string(reference))
      }
    }
    Error(#(reason, _meta, _env, _k)) -> Error(simple_debug.describe(reason))
  }
}

fn latest(hub: Hub, package) {
  list.filter(hub.releases, fn(release) { release.package == package })
  |> list.last
  |> result.map(fn(release) { release.module })
}

fn release(hub: Hub, package, version) {
  list.find(hub.releases, fn(release) {
    release.package == package && release.version == version
  })
  |> result.map(fn(release) { release.module })
}

/// Call an EYG function with one argument.
pub fn call(function: Value, argument: Value) -> Result(Value, String) {
  expression.call(function, [#(argument, [])])
  |> result.map_error(fn(debug) { simple_debug.describe(debug.0) })
}
