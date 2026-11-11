//// This module is similar to loam/execute BUT it's not the beam plaform instead it's the cloud platform.

import cloud/system
import eyg/hub/cache
import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/simple_debug
import eyg/interpreter/state
import eyg/interpreter/value as v
import eyg/ir/tree as ir
import eyg/parser
import gleam/crypto
import gleam/erlang/process
import gleam/httpc
import gleam/int
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import ogre/origin
import touch_grass/cryptography/hash
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/flip
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/now
import touch_grass/random
import touch_grass/sleep
import touch_grass/standard_error
import touch_grass/standard_out

pub type Output {
  StandardOut(String)
  StandardError(String)
}

/// same as loam/exectue.State
pub type State {
  State(origin: origin.Origin, cache: cache.Cache(Meta))
}

pub fn block(
  code: String,
  state: State,
  emit: fn(Output) -> Nil,
) -> #(Result(String, String), State) {
  case parser.all_from_string(code) {
    Error(reason) -> #(Error(parser.format_error(reason, code)), state)
    Ok(source) -> loop(block.execute(source, []), state, emit)
  }
}

fn loop(returned, state: State, emit) {
  case returned {
    Ok(#(value, _scope)) -> #(
      Ok(value |> option.map(simple_debug.inspect) |> option.unwrap("")),
      state,
    )
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) -> {
      case perform(label, lift, emit) {
        Ok(value) -> loop(block.resume(value, env, k), state, emit)
        Error(reason) -> #(Error(reason), state)
      }
    }
    Error(#(break.UndefinedReference(reference), _, env, k)) -> {
      let #(value, cache) = lookup(reference, state)
      let state = State(..state, cache:)
      case value {
        Ok(value) -> loop(block.resume(value, env, k), state, emit)
        Error(reason) -> #(Error(reason), state)
      }
    }
    Error(debug) -> #(Error(simple_debug.describe(debug.0)), state)
  }
}

fn perform(label, lift, emit) {
  use effect <- result.try(
    interface.cast(computer.effects(), label, lift)
    |> result.map_error(simple_debug.describe),
  )
  case effect {
    computer.StandardOut(text) -> {
      emit(StandardOut(text))
      Ok(standard_out.encode(Nil))
    }
    computer.StandardError(text) -> {
      emit(StandardError(text))
      Ok(standard_error.encode(Nil))
    }
    computer.AppendFile(_) -> Error("Unhandled effect: " <> label)
    computer.CreateKey(_) -> Error("Unhandled effect: " <> label)
    computer.Cwd -> cwd()
    computer.DecodeJson(bytes) -> decode_json(bytes)
    computer.DeleteFile(path: _) -> Error("Unhandled effect: " <> label)
    computer.Env(name:) -> get_env(name)
    computer.Exit(status: _) -> Error("Unhandled effect: " <> label)
    computer.EygParse(source: _) -> Error("Unhandled effect: " <> label)
    computer.Fetch(request) -> fetch(request)
    computer.Flip -> flip()
    computer.Hash(input) -> hash(input)
    computer.MakeDirectory(path: _) -> Error("Unhandled effect: " <> label)
    computer.Now -> now()
    computer.Random(max) -> random(max)
    computer.ReadDirectory(path: _) -> Error("Unhandled effect: " <> label)
    computer.ReadFile(_) -> Error("Unhandled effect: " <> label)
    computer.Sign(_) -> Error("Unhandled effect: " <> label)
    computer.Sleep(milliseconds) -> sleep(milliseconds)
    computer.StandardIn -> Error("Unhandled effect: " <> label)
    computer.WriteFile(_) -> Error("Unhandled effect: " <> label)
  }
}

pub type Meta =
  #(Int, Int)

pub fn lookup(
  reference: ir.Reference,
  state: State,
) -> #(Result(state.Value(#(Int, Int)), String), cache.Cache(Meta)) {
  let refresh = case reference {
    ir.Content(_) | ir.Relative(_) -> False
    _ -> True
  }
  let cache = case refresh {
    False -> state.cache
    True -> flush(cache.pull(state.cache), state.origin)
  }
  let missing = simple_debug.describe(break.UndefinedReference(reference))
  let cid = case reference {
    ir.Content(cid) -> Ok(cid)
    ir.Package(name) ->
      cache.package(cache, name) |> result.map(fn(entry) { entry.module })
    ir.Version(name, version) -> cache.unbound_release(cache, name, version)
    ir.Pinned(release) ->
      case cache.release(cache, release) {
        cache.Available(cid) -> Ok(cid)
        _ -> Error(Nil)
      }
    ir.Relative(_) -> Error(Nil)
  }
  case cid, cache.cursor_status {
    _, cache.PullFailed(reason) if refresh -> #(Error(reason), cache)
    Error(Nil), _ -> #(Error(missing), cache)
    Ok(cid), _ -> {
      let cache = flush(cache.fetch(cache, cid), state.origin)
      let value = case cache.get_module(cache, cid) {
        Ok(module) -> Ok(module.value)
        Error(cache.Failed(reason)) -> Error(reason)
        Error(cache.Invalid(reason)) -> Error(simple_debug.describe(reason))
        Error(_) -> Error(missing)
      }
      #(value, cache)
    }
  }
}

fn flush(cache: cache.Cache(Meta), origin) -> cache.Cache(Meta) {
  let #(cache, actions) = cache.flush(cache)
  case actions {
    [] -> cache
    _ -> {
      let cache =
        list.fold(actions, cache, fn(cache, action) {
          cache.update(cache, compute(action, origin), fn(_) { #(0, 0) }).0
        })
      flush(cache, origin)
    }
  }
}

fn compute(action, origin) {
  cache.compute(action, origin, system.fetch, system.hash)(fn(x) { x })
}

fn cwd() {
  Ok(v.ok(v.String("/")))
}

fn decode_json(bytes) {
  Ok(decode_json.sync(bytes))
}

fn get_env(_name) {
  Ok(v.error(v.unit()))
}

fn fetch(request) {
  httpc.send_bits(request)
  |> result.map_error(string.inspect)
  |> fetch.encode
  |> Ok
}

fn flip() {
  Ok(flip.encode(flip.sync()))
}

fn hash(input) {
  let hash.Input(algorithm: hash.Sha256, bytes:) = input
  Ok(hash.encode(crypto.hash(crypto.Sha256, bytes)))
}

fn now() {
  Ok(now.encode(now.sync()))
}

fn random(max) {
  Ok(random.encode(random.sync(max)))
}

fn sleep(milliseconds) {
  process.sleep(int.max(0, milliseconds))
  Ok(sleep.encode(Nil))
}
