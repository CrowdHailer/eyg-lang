//// This module is similar to loam/execute BUT it's not the beam plaform instead it's the cloud platform.

import eyg/interpreter/block
import eyg/interpreter/break
import eyg/interpreter/simple_debug
import eyg/interpreter/value as v
import eyg/parser
import gleam/crypto
import gleam/erlang/process
import gleam/httpc
import gleam/int
import gleam/option
import gleam/result
import gleam/string
import touch_grass/cryptography/hash
import touch_grass/decode_json
import touch_grass/fetch
import touch_grass/flip
import touch_grass/harness/computer
import touch_grass/interface
import touch_grass/now
import touch_grass/random
import touch_grass/sleep
import touch_grass/standard_out

pub fn block(code: String, emit: fn(String) -> Nil) -> Result(String, String) {
  use source <- result.try(
    parser.all_from_string(code)
    |> result.map_error(parser.format_error(_, code)),
  )
  block.execute(source, [])
  |> loop(emit)
}

fn loop(returned, emit) {
  case returned {
    Ok(#(value, _scope)) ->
      Ok(value |> option.map(simple_debug.inspect) |> option.unwrap(""))
    Error(#(break.UnhandledEffect(label, lift), _, env, k)) -> {
      use effect <- result.try(
        interface.cast(computer.effects(), label, lift)
        |> result.map_error(simple_debug.describe),
      )
      use value <- result.try(case effect {
        computer.StandardOut(text) | computer.StandardError(text) -> {
          emit(text)
          Ok(standard_out.encode(Nil))
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
      })
      loop(block.resume(value, env, k), emit)
    }
    Error(debug) -> Error(simple_debug.describe(debug.0))
  }
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
