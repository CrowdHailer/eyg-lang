//// Implement the computer harness by composing Loam effects, without running them.

import eyg/interpreter/state
import eyg/interpreter/value as v
import filepath
import gleam/bit_array
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import kryptos/eddsa
import loam/source
import loam/system
import midas/effect as host_effect
import simplifile
import touch_grass/cryptography/create_key
import touch_grass/cryptography/hash
import touch_grass/cryptography/sign
import touch_grass/decode_json
import touch_grass/env
import touch_grass/eyg_parse
import touch_grass/fetch
import touch_grass/file_system/append_file
import touch_grass/file_system/cwd
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
import touch_grass/standard_in
import touch_grass/standard_out

pub fn cast(
  label: String,
  lift: state.Value(m),
) -> Result(computer.Effect, state.Reason(m)) {
  interface.cast(computer.effects(), label, lift)
}

pub fn effects() -> interface.Harness(computer.Effect, meta) {
  computer.effects()
}

pub fn extrinsic(
  effect: computer.Effect,
  origin: source.Origin,
) -> system.Effect(v.Value(a, b)) {
  case effect {
    computer.AppendFile(input) ->
      system.map(append_file(origin, input), append_file.encode)
    computer.CreateKey(request) ->
      system.map(create_key(request), create_key.encode)
    computer.Cwd -> system.map(system.cwd(), cwd.encode)
    computer.DecodeJson(encoded) -> system.Done(decode_json.sync(encoded))
    computer.DeleteFile(path) ->
      system.map(delete_file(origin, path), delete_file.encode)
    computer.Env(name) -> system.map(system.env(name), env.encode)
    computer.Exit(status) -> system.Exit(status)
    computer.EygParse(code) ->
      system.Done(source.parse(code, origin) |> eyg_parse.encode)
    computer.Fetch(request) -> {
      use response <- system.map(system.fetch(request))
      response |> result.map_error(string.inspect) |> fetch.encode
    }
    computer.Flip -> {
      use value <- system.map(system.random(2))
      flip.encode(int.is_even(value))
    }
    computer.Hash(input) -> {
      let hash.Input(algorithm: hash.Sha256, bytes:) = input
      system.map(system.hash(host_effect.Sha256, bytes), hash.encode)
    }
    computer.MakeDirectory(path) ->
      system.map(make_directory(origin, path), make_directory.encode)
    computer.Now -> system.map(system.now(), now.encode)
    computer.Random(max) -> system.map(system.random(max), random.encode)
    computer.ReadDirectory(path) ->
      system.map(read_directory(origin, path), read_directory.encode)
    computer.ReadFile(input) ->
      system.map(read_file(origin, input), read_file.encode)
    computer.Sign(request) -> system.Done(sign(request) |> sign.encode)
    computer.Sleep(milliseconds) ->
      system.map(system.wait(milliseconds), sleep.encode)
    computer.StandardError(text) ->
      system.map(system.write_stderr(text), standard_error.encode)
    computer.StandardIn -> {
      use input <- system.map(system.stdin())
      input |> result.map(bit_array.from_string) |> standard_in.encode
    }
    computer.StanardOut(text) ->
      system.map(system.write_stdout(text), standard_out.encode)
    computer.WriteFile(input) ->
      system.map(write_file(origin, input), write_file.encode)
  }
}

pub fn make_directory(origin: source.Origin, path: String) {
  use path <- system.then(source.resolve_filepath(origin, path))
  use path <- system.try(path)
  system.create_directory(path)
}

pub fn read_file(origin: source.Origin, input: read_file.Input) {
  let read_file.Input(path:, offset:, limit:) = input
  use path <- system.then(source.resolve_filepath(origin, path))
  use path <- system.try(path)
  use contents <- system.map(system.read_file_range(path, offset, limit))
  result.map_error(contents, simplifile.describe_error)
}

pub fn write_file(origin: source.Origin, input: write_file.Input) {
  let write_file.Input(path:, contents:) = input
  use path <- system.then(source.resolve_filepath(origin, path))
  use path <- system.try(path)
  use result <- system.map(system.write_file_bits(path, contents))
  result.map_error(result, simplifile.describe_error)
}

pub fn append_file(origin: source.Origin, input: append_file.Input) {
  let append_file.Input(path:, contents:) = input
  use path <- system.then(source.resolve_filepath(origin, path))
  use path <- system.try(path)
  use result <- system.map(system.append_file_bits(path, contents))
  result.map_error(result, simplifile.describe_error)
}

pub fn delete_file(origin: source.Origin, path: String) {
  use path <- system.then(source.resolve_filepath(origin, path))
  use path <- system.try(path)
  use result <- system.map(system.delete_file(path))
  result.map_error(result, simplifile.describe_error)
}

pub fn read_directory(origin: source.Origin, path: String) {
  use path <- system.then(source.resolve_filepath(origin, path))
  use path <- system.try(path)
  use children <- system.then(system.read_directory(path))
  use children <- system.try(result.map_error(
    children,
    simplifile.describe_error,
  ))
  use entries <- system.map(
    system.traverse(children, fn(child) {
      use info <- system.map(system.file_info(filepath.join(path, child)))
      case info {
        Ok(system.Metadata(simplifile.File, size)) ->
          Ok(#(child, read_directory.File(size)))
        Ok(system.Metadata(simplifile.Directory, _)) ->
          Ok(#(child, read_directory.Directory))
        _ -> Error(Nil)
      }
    }),
  )
  entries
  |> list.filter_map(fn(entry) { entry })
  |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
  |> Ok
}

pub fn create_key(request) {
  case request {
    create_key.Eddsa -> {
      use keys <- system.map(system.generate_key())
      Ok(create_key.EddsaKey(
        public_key: eddsa.public_key_to_bytes(keys.public_key),
        private_key: eddsa.to_bytes(keys.private_key),
      ))
    }
  }
}

/// Signing with a supplied key is deterministic and needs no host effect.
pub fn sign(request) {
  case request {
    sign.EddsaSign(private_key:, data:) ->
      case eddsa.from_bytes(eddsa.Ed25519, private_key) {
        Ok(#(key, _)) -> Ok(eddsa.sign(key, data))
        Error(Nil) -> Error("invalid Ed25519 private key")
      }
  }
}
