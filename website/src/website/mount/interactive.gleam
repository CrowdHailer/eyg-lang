import eyg/interpreter/block
import eyg/interpreter/state as istate
import eyg/ir/tree as ir
import gleam/javascript/promise
import gleam/listx
import gleam/option.{type Option, Some}

import morph/analysis
import morph/editable as e

import website/sync/cache

// The interactive mount always evaluates new code
// it is used in the example -> rename from snippet

pub type Scope =
  List(#(String, analysis.Value))

pub type Return =
  Result(#(Option(analysis.Value), Scope), istate.Debug(analysis.Path))

pub type RuntimeEffect {
  RuntimeEffect(label: String, lift: analysis.Value, reply: analysis.Value)
}

pub fn effect_types(effects: List(#(String, analysis.EffectSpec))) {
  listx.value_map(effects, fn(details) { #(details.0, details.1) })
}

pub fn evaluate(editable, scope, cache) {
  e.to_annotated(editable, [])
  |> ir.clear_annotation
  |> block.execute(scope)
  |> cache.run(cache, block.resume)
}
