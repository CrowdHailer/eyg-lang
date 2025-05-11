import eyg/interpreter/break
import eyg/interpreter/builtin
import eyg/interpreter/state
import eyg/interpreter/value as v
import gleam/dict
import gleam/javascript/promise
import gleam/list

pub fn resume(value, env, k) {
  loop(state.step(state.V(value), env, k))
}

pub fn loop(next) {
  case next {
    state.Loop(c, e, k) -> loop(state.step(c, e, k))
    state.Break(result) -> result
  }
}

// Solves the situation that JavaScript suffers from coloured functions
// To eval code that may be async needs to return a promise of a result
pub fn await(ret) {
  case ret {
    Error(#(break.UnhandledEffect("Await", v.Promise(p)), _meta, env, k)) -> {
      use return <- promise.await(p)
      await(loop(state.step(state.V(return), env, k)))
    }
    other -> promise.resolve(other)
  }
}

pub fn execute(exp, scope) {
  loop(state.step(state.E(exp), new_env(scope), state.Empty(dict.new())))
}

// f should have all the required env information
pub fn call(f, args) {
  let env = new_env([])
  let h = dict.new()
  let k =
    list.fold_right(args, state.Empty(h), fn(k, arg) {
      let #(value, meta) = arg
      state.Stack(state.CallWith(value, env), meta, k)
    })
  loop(state.step(state.V(f), env, k))
}

// This assumes only scope needs passing around
pub fn new_env(scope) {
  state.Env(scope: scope, references: dict.new(), builtins: builtins())
}

fn builtins() {
  dict.new()
  |> dict.insert("equal", builtin.equal)
  |> dict.insert("fix", builtin.fix)
  |> dict.insert("fixed", builtin.fixed)
  // integer
  |> dict.insert("int_compare", builtin.int_compare)
  |> dict.insert("int_add", builtin.add)
  |> dict.insert("int_subtract", builtin.subtract)
  |> dict.insert("int_multiply", builtin.multiply)
  |> dict.insert("int_divide", builtin.divide)
  |> dict.insert("int_absolute", builtin.absolute)
  |> dict.insert("int_parse", builtin.int_parse)
  |> dict.insert("int_to_string", builtin.int_to_string)
  // String
  |> dict.insert("string_append", builtin.string_append)
  |> dict.insert("string_split", builtin.string_split)
  |> dict.insert("string_split_once", builtin.string_split_once)
  |> dict.insert("string_replace", builtin.string_replace)
  |> dict.insert("string_uppercase", builtin.string_uppercase)
  |> dict.insert("string_lowercase", builtin.string_lowercase)
  |> dict.insert("string_starts_with", builtin.string_starts_with)
  |> dict.insert("string_ends_with", builtin.string_ends_with)
  |> dict.insert("string_length", builtin.string_length)
  |> dict.insert("string_to_binary", builtin.string_to_binary)
  |> dict.insert("string_from_binary", builtin.string_from_binary)
  // Binary
  |> dict.insert("binary_from_integers", builtin.binary_from_integers)
  |> dict.insert("binary_fold", builtin.binary_fold)
  // List
  |> dict.insert("list_pop", builtin.list_pop)
  |> dict.insert("list_fold", builtin.list_fold)
}
