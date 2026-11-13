//// This module is similar to loam/execute BUT it's not the beam plaform instead it's the cloud platform.

import cloud/beam/file_system
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
import touch_grass/file_system/append_file
import touch_grass/file_system/delete_file
import touch_grass/file_system/make_directory
import touch_grass/file_system/read_directory
import touch_grass/file_system/read_file
import touch_grass/file_system/write_file
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
  files: file_system.State,
  emit: fn(Output) -> Nil,
) -> #(Result(String, String), State, file_system.State) {
  case parser.all_from_string(code) {
    Error(reason) -> #(Error(parser.format_error(reason, code)), state, files)
    Ok(source) -> loop(block.execute(source, []), state, files, emit)
  }
}

fn loop(returned, state: State, files, emit) {
  case returned {
    Ok(#(value, _scope)) -> #(
      Ok(value |> option.map(simple_debug.inspect) |> option.unwrap("")),
      state,
      files,
    )
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) -> {
      let #(outcome, files) = perform(label, lift, files, emit)
      case outcome {
        Ok(value) -> loop(block.resume(value, env, k), state, files, emit)
        Error(reason) -> #(Error(reason), state, files)
      }
    }
    Error(#(break.UndefinedReference(reference), _, env, k)) -> {
      let #(value, cache) = lookup(reference, state)
      let state = State(..state, cache:)
      case value {
        Ok(value) -> loop(block.resume(value, env, k), state, files, emit)
        Error(reason) -> #(Error(reason), state, files)
      }
    }
    Error(debug) -> #(Error(simple_debug.describe(debug.0)), state, files)
  }
}

fn perform(label, lift, files, emit) {
  case interface.cast(computer.effects(), label, lift) {
    Error(reason) -> #(Error(simple_debug.describe(reason)), files)
    Ok(effect) -> perform_effect(effect, label, files, emit)
  }
}

fn perform_effect(effect, label, files, emit) {
  case effect {
    computer.StandardOut(text) -> {
      emit(StandardOut(text))
      #(Ok(standard_out.encode(Nil)), files)
    }
    computer.StandardError(text) -> {
      emit(StandardError(text))
      #(Ok(standard_error.encode(Nil)), files)
    }
    computer.AppendFile(input) -> {
      let #(outcome, files) =
        file_system.append(files, input.path, input.contents)
      #(Ok(append_file.encode(outcome)), files)
    }
    computer.Cwd -> #(cwd(), files)
    computer.DecodeJson(bytes) -> #(decode_json(bytes), files)
    computer.DeleteFile(path) -> {
      let #(outcome, files) = file_system.delete(files, path)
      #(Ok(delete_file.encode(outcome)), files)
    }
    computer.Env(name:) -> #(get_env(name), files)
    computer.Fetch(request) -> #(fetch(request), files)
    computer.Flip -> #(flip(), files)
    computer.Hash(input) -> #(hash(input), files)
    computer.MakeDirectory(path) -> {
      let #(outcome, files) = file_system.make_directory(files, path)
      #(Ok(make_directory.encode(outcome)), files)
    }
    computer.Now -> #(now(), files)
    computer.Random(max) -> #(random(max), files)
    computer.ReadDirectory(path) -> #(
      Ok(file_system.read_directory(files, path) |> read_directory.encode),
      files,
    )
    computer.ReadFile(input) -> #(
      Ok(
        file_system.read(files, input.path, input.offset, input.limit)
        |> read_file.encode,
      ),
      files,
    )
    computer.Sleep(milliseconds) -> #(sleep(milliseconds), files)
    computer.WriteFile(input) -> {
      let #(outcome, files) =
        file_system.write(files, input.path, input.contents)
      #(Ok(write_file.encode(outcome)), files)
    }
    computer.CreateKey(_)
    | computer.Exit(_)
    | computer.EygParse(_)
    | computer.Sign(_)
    | computer.StandardIn -> #(Error("Unhandled effect: " <> label), files)
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
