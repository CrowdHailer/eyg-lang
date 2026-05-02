//// This module doesn't keep a state or decide the key bindings or define effects
//// Nested objects that look like mini apps has been a complexity multiplier
//// It does not track running state or type checking context
//// This module contains just functions from buffer transformations to a editable states
//// The editable states are consistent over all eyg.run pages
//// This shouldn't move to morph because it makes descisions on representing to the user
//// i.e. all choose labels are represented the same way
//// This doesn't handle Async like copy paste
//// separate command mapping
//// This module also includes the logic from inference types to a rendered version of that using debug.mono
//// This builds on run_context and harness because it is the top understanding of these concept of manipulating in the browser

import eyg/analysis/inference/levels_j/contextual as infer
import eyg/analysis/type_/binding/debug
import gleam/dict
import gleam/list
import gleam/listx
import gleam/result
import morph/picker
import multiformats/cid/v1
import website/components/snippet
import website/harness/harness
import website/routes/workspace/buffer.{type Buffer}

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
  Resolved(fn(infer.Context) -> buffer.Buffer)
  UserInput(UserInput)
}

pub type UserInput {
  PickSingle(picker.Picker, Rebuild(String))
  PickCid(picker.Picker, Rebuild(v1.Cid))
  PickRelease(picker.Picker, Rebuild(#(String, Int, v1.Cid)))
  EnterText(String, Rebuild(String))
  EnterInteger(Int, Rebuild(Int))
}

pub type Rebuild(t) =
  fn(t, infer.Context) -> buffer.Buffer

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
  let scope = buffer.target_scope(buffer) |> result.unwrap([])
  let hints = listx.value_map(scope, snippet.render_poly)
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
  Resolved(rebuild(arity, _))
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
      let rebuild = fn(label, context) { rebuild([label], context) }
      UserInput(PickSingle(picker.new("", []), rebuild))
    }
    _ -> Resolved(rebuild(listx.keys(hints), _))
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
  let hints = listx.value_map(buffer.varients(buffer), debug.mono)
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

pub fn insert_case() {
  Operation(name: "insert match", apply: do_insert_case)
}

fn do_insert_case(buffer) {
  use rebuild <- result.map(buffer.match(buffer))

  let hints = listx.value_map(buffer.varients(buffer), debug.mono)
  case hints {
    [] -> {
      let rebuild = fn(label, context) { rebuild([label], context) }
      UserInput(PickSingle(picker.new("", []), rebuild))
    }
    _ -> Resolved(rebuild(listx.keys(hints), _))
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

pub fn perform() {
  Operation(name: "perform", apply: do_perform)
}

fn do_perform(buffer) {
  use rebuild <- result.map(buffer.perform(buffer))
  let hints = effect_hints()
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

pub fn insert_handle() {
  Operation(name: "insert handle", apply: do_insert_handle)
}

fn do_insert_handle(buffer) {
  use rebuild <- result.map(buffer.insert_handle(buffer))
  let hints = effect_hints()
  UserInput(PickSingle(picker.new("", hints), rebuild))
}

fn effect_hints() {
  list.map(harness.types(harness.effects()), fn(effect) {
    let #(key, types) = effect
    #(key, snippet.render_effect(types))
  })
}

pub fn insert_builtin() {
  Operation(name: "insert builtin", apply: do_insert_builtin)
}

fn do_insert_builtin(buffer) {
  use rebuild <- result.map(buffer.insert_builtin(buffer))
  let hints = listx.value_map(infer.builtins(), snippet.render_poly)
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
  use rebuild <- result.map(buffer.insert_release(buffer))
  let hints =
    list.map(dict.to_list(modules), fn(module) {
      let #(#(name, _ext), buffer) = module
      #(name, snippet.render_poly(infer.poly_type(buffer.analysis)))
    })
  UserInput(PickRelease(picker.new("", hints), rebuild))
}

pub fn choose_release() {
  Operation(name: "choose release", apply: do_choose_release)
}

fn do_choose_release(buffer) {
  todo
  // let buffer = active(state)
  // use rebuild <- try(buffer.insert_release(buffer), state, "insert release")
  // let hints =
  //   list.map(package_choice(state), fn(release) {
  //     todo
  //     // let analysis.Release(package:, version:, ..) = release
  //     // #(package, int.to_string(version))
  //   })

  // let picker = picker.new("", hints)
  // let state = State(..state, mode: ChoosingPackage(picker:, rebuild:))
  // #(state, [])
}

fn package_choice(state) {
  todo
  // let State(sync: client.Client(cache:, ..), ..) = state
  // cache.package_index(cache)
}

/// create an operation from better actions that always resolve
fn transform(name, func) {
  let apply = fn(buffer) { result.map(func(buffer), Resolved) }
  Operation(name, apply)
}
