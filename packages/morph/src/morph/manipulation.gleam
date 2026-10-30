//// Shared editing operations for the web and terminal workspace.
//// Effects and published package index are provided by the caller.
//// Async IO and key bindings remain with the frontend.
//// State management also remains with the top level application.
//// 
//// Edits return buffers with invalidated analysis. The caller drives
//// `buffer.check` after applying an edit, using its current scope and cache.
//// 
//// Optional improvements
//// - This module/package could depend on the sans-io implementation of a cache
////   That approach could allow better shared search functionality when the amount of packages grows.

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding
import eyg/analysis/type_/binding/debug
import eyg/ir/tree as ir
import gleam/dict
import gleam/int
import gleam/list
import gleam/listx
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import morph/buffer.{type Buffer}
import morph/picker
import multiformats/cid/v1

/// Represents an available manipulation that can be performed on the AST.
/// `name` is the human-readable label (e.g. "Delete", "Insert Variable").
/// `apply` manipulates the current state and either fails with an error, 
/// or succeeds with a `NextStep`.
pub type Operation {
  Operation(name: String, apply: fn(Buffer) -> Result(Continue, Nil))
}

/// Describes what (if anything) the user must decide after an operation
/// has been initiated. `Resolved` means no further input is needed;
/// the other variants carry the choices the user must pick from.
pub type Continue {
  Resolved(buffer.Buffer)
  UserInput(UserInput)
}

pub type UserInput {
  PickSingle(picker.Picker, Rebuild(String))
  PickCid(picker.Picker, Rebuild(v1.Cid))
  PickRelease(picker.Picker, Rebuild(ir.Release))
  EnterText(String, Rebuild(String))
  EnterInteger(Int, Rebuild(Int))
}

pub type Rebuild(t) =
  fn(t) -> buffer.Buffer

// CORE

pub fn delete() {
  transform("delete", buffer.delete)
}

pub fn redo() {
  transform("redo", buffer.redo)
}

pub fn undo() {
  transform("undo", buffer.undo)
}

pub fn insert() {
  Operation(name: "insert", apply: do_insert)
}

fn do_insert(buffer) {
  use #(value, rebuild) <- result.map(buffer.insert(buffer))
  UserInput(PickSingle(picker.new(value, []), rebuild))
}

// PRIMITIVES
pub fn insert_binary() {
  transform("create list", buffer.insert_binary)
}

pub fn insert_string() {
  Operation(name: "insert string", apply: do_insert_string)
}

fn do_insert_string(buffer) {
  use #(value, rebuild) <- result.map(buffer.insert_string(buffer))
  UserInput(EnterText(value, rebuild))
}

pub fn insert_integer() {
  Operation(name: "insert integer", apply: do_insert_integer)
}

fn do_insert_integer(buffer) {
  use #(value, rebuild) <- result.map(buffer.insert_integer(buffer))
  UserInput(EnterInteger(value, rebuild))
}

// FUNCTIONS

pub fn insert_variable() {
  Operation(name: "insert variable", apply: do_insert_variable)
}

fn do_insert_variable(buffer) {
  use rebuild <- result.map(buffer.insert_variable(buffer))
  let scope =
    buffer.target_scope(buffer)
    |> result.unwrap([])
    |> listx.key_unique()
    |> listx.key_filter_fn(fn(var) {
      !string.starts_with(var, "_") && !string.starts_with(var, "$")
    })

  let hints = case buffer.analysis {
    None -> []
    Some(analysis) ->
      listx.value_map(scope, fn(scheme) {
        let #(type_, bindings) =
          binding.instantiate(scheme, 0, analysis.bindings)
        binding.resolve(type_, bindings) |> debug.mono
      })
  }
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

pub fn insert_function() {
  Operation("create function", do_insert_function)
}

fn do_insert_function(buffer) {
  use rebuild <- result.map(buffer.insert_function(buffer))
  UserInput(PickSingle(picker.new("", []), rebuild))
}

pub fn call_once() {
  transform("call", buffer.call_once)
}

pub fn call_function() {
  Operation(name: "call function", apply: do_call_function)
}

fn do_call_function(buffer) {
  use rebuild <- result.map(buffer.call_many(buffer))
  let arity = buffer.target_arity(buffer) |> result.unwrap(1)
  Resolved(rebuild(arity))
}

pub fn call_with() {
  transform("call", buffer.call_with)
}

// COMPOUND TYPES List,Record,Union

pub fn create_empty_list() {
  transform("create list", buffer.create_empty_list)
}

pub fn create_list() {
  transform("create list", buffer.create_list)
}

pub fn spread() {
  transform("spread", buffer.spread)
}

pub fn create_record() {
  Operation("create record", do_create_record)
}

fn do_create_record(buffer) {
  use rebuild <- result.map(buffer.create_record(buffer))
  let hints = buffer.fields(buffer)
  case hints {
    [] -> {
      let rebuild = fn(label) { rebuild([label]) }
      UserInput(PickSingle(picker.new("", []), rebuild))
    }
    _ -> Resolved(rebuild(listx.keys(hints)))
  }
}

pub fn create_empty_record() {
  transform("create empty record", buffer.create_empty_record)
}

pub fn select_field() {
  Operation(name: "select field", apply: do_select_field)
}

fn do_select_field(buffer) {
  use rebuild <- result.map(buffer.select_field(buffer))
  let hints = listx.value_map(buffer.fields(buffer), debug.mono)
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

pub fn overwrite() {
  Operation(name: "overwrite", apply: do_overwrite)
}

fn do_overwrite(buffer) {
  use rebuild <- result.map(buffer.overwrite(buffer))
  let hints = listx.value_map(buffer.fields(buffer), debug.mono)
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

pub fn insert_tag() {
  Operation(name: "tag", apply: do_insert_tag)
}

fn do_insert_tag(buffer) {
  use rebuild <- result.map(buffer.tag(buffer))
  let hints = listx.value_map(buffer.variants(buffer), debug.mono)
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

pub fn insert_case() {
  Operation(name: "insert match", apply: do_insert_case)
}

fn do_insert_case(buffer) {
  use rebuild <- result.map(buffer.match(buffer))

  let hints = listx.value_map(buffer.variants(buffer), debug.mono)
  case hints {
    [] -> {
      let rebuild = fn(label) { rebuild([label]) }
      UserInput(PickSingle(picker.new("", []), rebuild))
    }
    _ -> Resolved(rebuild(listx.keys(hints)))
  }
}

pub fn insert_before() {
  Operation(name: "insert before", apply: do_insert_before)
}

fn do_insert_before(buffer) {
  use choice <- result.map(buffer.insert_before(buffer))
  case choice {
    buffer.Done(rebuild) -> Resolved(rebuild)
    buffer.WithString(rebuild) ->
      UserInput(PickSingle(picker.new("", []), rebuild))
  }
}

pub fn insert_after() {
  Operation(name: "insert after", apply: do_insert_after)
}

fn do_insert_after(buffer) {
  use choice <- result.map(buffer.insert_after(buffer))
  case choice {
    buffer.Done(rebuild) -> Resolved(rebuild)
    buffer.WithString(rebuild) ->
      UserInput(PickSingle(picker.new("", []), rebuild))
  }
}

// BLOCKS let and assignement

pub fn assign() {
  Operation("assign", do_assign)
}

fn do_assign(buffer) {
  use rebuild <- result.map(buffer.assign(buffer))
  UserInput(PickSingle(picker.new("", []), rebuild))
}

pub fn assign_before() {
  Operation("assign before", do_assign_before)
}

fn do_assign_before(buffer) {
  use rebuild <- result.map(buffer.assign_before(buffer))
  UserInput(PickSingle(picker.new("", []), rebuild))
}

// EFFECTS perform, handle

pub fn perform(effects) {
  Operation(name: "perform", apply: do_perform(_, effects))
}

fn do_perform(buffer, effects) {
  use rebuild <- result.map(buffer.perform(buffer))
  let hints = effect_hints(effects)
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

pub fn insert_handle(effects) {
  Operation(name: "insert handle", apply: do_insert_handle(_, effects))
}

fn do_insert_handle(buffer, effects) {
  use rebuild <- result.map(buffer.insert_handle(buffer))
  let hints = effect_hints(effects)
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

fn effect_hints(effects) {
  list.map(effects, fn(effect) {
    let #(key, types) = effect
    #(key, render_effect(types))
  })
}

pub fn poly(poly) {
  let #(type_, _) = binding.instantiate(poly, 0, dict.new())
  debug.mono(type_)
}

fn render_effect(eff) {
  let #(lift, reply) = eff
  string.concat([debug.mono(lift), " : ", debug.mono(reply)])
}

pub fn insert_builtin() {
  Operation(name: "insert builtin", apply: do_insert_builtin)
}

fn do_insert_builtin(buffer) {
  use rebuild <- result.map(buffer.insert_builtin(buffer))
  let hints = listx.value_map(infer.builtins(), poly)
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

// References

pub fn insert_reference() {
  Operation(name: "insert reference", apply: do_insert_reference)
}

fn do_insert_reference(buffer) {
  use rebuild <- result.map(buffer.insert_reference(buffer))
  UserInput(PickCid(picker.new("", []), rebuild))
}

pub fn choose_module(modules) {
  Operation(name: "choose module", apply: do_choose_module(_, modules))
}

fn do_choose_module(buffer, modules: dict.Dict(_, buffer.Buffer)) {
  use insert <- result.map(buffer.insert_explicit_reference(buffer))
  let choices =
    modules
    |> dict.to_list
    |> list.map(fn(module) {
      let #(#(name, _ext), _buffer) = module
      #(name, ir.Relative("/" <> name <> ".eyg.json"))
    })
    |> dict.from_list
  let rebuild = fn(name) {
    case dict.get(choices, name) {
      Ok(reference) -> insert(reference)
      Error(Nil) -> buffer
    }
  }
  let hints =
    list.map(dict.to_list(modules), fn(module) {
      let #(#(name, _ext), buffer) = module
      let hint = case buffer.analysis {
        None -> "unchecked"
        Some(analysis) -> poly(infer.poly_type(analysis))
      }
      #(name, hint)
    })
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

pub fn choose_release(packages: List(#(String, Int))) {
  Operation(name: "choose release", apply: do_choose_release(_, packages))
}

fn do_choose_release(buffer, packages) {
  use rebuild <- result.map(buffer.insert_release(buffer))

  let hints =
    list.map(packages, fn(release) {
      let #(package, version) = release
      #(package, int.to_string(version))
    })

  UserInput(PickRelease(picker.new("", hints), rebuild))
}

/// create an operation from better actions that always resolve
fn transform(name, func) {
  let apply = fn(buffer) { result.map(func(buffer), Resolved) }
  Operation(name, apply)
}
