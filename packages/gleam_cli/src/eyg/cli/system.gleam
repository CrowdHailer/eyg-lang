import eyg/cli/internal/bun_platform
import eyg/cli/internal/crypto
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/result
import kryptos/eddsa
import midas/effect
import simplifile
import untethered/keypair

// This exists for testing as the runner can be defined straight away.
pub type Effect(a) {
  Done(a)
  CreateDirectory(String, fn(Result(Nil, String)) -> Effect(a))
  Fetch(
    Request(BitArray),
    fn(Result(Response(BitArray), effect.FetchError)) -> Effect(a),
  )
  GenerateKey(
    fn(keypair.Keypair(eddsa.PrivateKey, eddsa.PublicKey)) -> Effect(a),
  )
  ReadFile(String, fn(Result(String, String)) -> Effect(a))
  SetPermissions(String, Int, fn(Result(Nil, String)) -> Effect(a))
  Stdin(fn(Result(String, String)) -> Effect(a))
  Stdout(String, fn(Nil) -> Effect(a))
  Wait(Int, fn(Nil) -> Effect(a))
  WriteFile(String, String, fn(Result(Nil, String)) -> Effect(a))
}

pub fn generate_key() {
  GenerateKey(Done)
}

pub fn fetch(
  request: Request(BitArray),
) -> Effect(Result(Response(BitArray), effect.FetchError)) {
  Fetch(request, Done)
}

pub fn create_directory(path) {
  CreateDirectory(path, Done)
}

pub fn read_file(path) {
  ReadFile(path, Done)
}

pub fn write_file(path, contents) {
  WriteFile(path, contents, Done)
}

pub fn set_permissions(path, permissions) {
  SetPermissions(path, permissions, Done)
}

pub fn stdin() {
  Stdin(Done)
}

pub fn stdout(text) {
  Stdout(text, Done)
}

pub fn then(effect: Effect(a), func: fn(a) -> Effect(b)) -> Effect(b) {
  case effect {
    Done(value) -> func(value)
    GenerateKey(resume) ->
      GenerateKey(fn(keypair) { then(resume(keypair), func) })
    Fetch(request, resume) ->
      Fetch(request, fn(response) { then(resume(response), func) })
    CreateDirectory(path, resume) ->
      CreateDirectory(path, fn(response) { then(resume(response), func) })
    ReadFile(path, resume) ->
      ReadFile(path, fn(response) { then(resume(response), func) })
    WriteFile(path, contents, resume) ->
      WriteFile(path, contents, fn(response) { then(resume(response), func) })
    SetPermissions(path, permissions, resume) ->
      SetPermissions(path, permissions, fn(response) {
        then(resume(response), func)
      })
    Stdin(resume) -> Stdin(fn(response) { then(resume(response), func) })
    Stdout(text, resume) ->
      Stdout(text, fn(response) { then(resume(response), func) })
    Wait(timeout, resume) ->
      Wait(timeout, fn(response) { then(resume(response), func) })
  }
}

pub fn each(effects: List(Effect(Nil))) -> Effect(Nil) {
  case effects {
    [] -> Done(Nil)
    [effect, ..effects] -> {
      use Nil <- then(effect)
      each(effects)
    }
  }
}

pub fn try(
  result: Result(a, b),
  then: fn(a) -> Effect(Result(c, b)),
) -> Effect(Result(c, b)) {
  case result {
    Ok(value) -> then(value)
    Error(reason) -> Done(Error(reason))
  }
}

pub fn run(effect: Effect(a)) -> Promise(a) {
  case effect {
    Done(value) -> promise.resolve(value)
    GenerateKey(resume) -> run(resume(crypto.generate_key()))
    Fetch(request, resume) -> {
      use response <- promise.await(bun_platform.fetch(request)(promise.resolve))
      run(resume(response))
    }
    CreateDirectory(path, resume) -> run(resume(do_create_directory(path)))
    ReadFile(path, resume) -> run(resume(do_read_file(path)))
    WriteFile(path, contents, resume) ->
      run(resume(do_write_file(path, contents)))
    SetPermissions(path, permissions, resume) ->
      run(resume(do_set_permissions(path, permissions)))
    Stdin(resume) -> run(resume(read_stdin()))
    Stdout(text, resume) -> run(resume(io.println(text)))
    Wait(duration, resume) -> {
      use response <- promise.await(bun_platform.wait(duration)(promise.resolve))
      run(resume(response))
    }
  }
}

fn do_create_directory(path) {
  simplifile.create_directory_all(path)
  |> result.map_error(simplifile.describe_error)
}

fn do_write_file(path, contents) {
  simplifile.write(path, contents)
  |> result.map_error(simplifile.describe_error)
}

fn do_set_permissions(path, permissions) {
  simplifile.set_permissions_octal(path, permissions)
  |> result.map_error(simplifile.describe_error)
}

fn format_file_error(path: String, err: simplifile.FileError) -> String {
  let #(description, hint) = case err {
    simplifile.Enoent -> #(
      "no such file: " <> path,
      "check the path and that the file exists, relative to the current working directory",
    )
    simplifile.Eisdir -> #(
      "expected a file but found a directory: " <> path,
      "pass the path to a source file, not a directory",
    )
    simplifile.Eacces -> #(
      "permission denied reading: " <> path,
      "check the file is readable by the current user",
    )
    _ -> #(
      "could not read " <> path <> ": " <> simplifile.describe_error(err),
      "check the path is correct and readable",
    )
  }
  "error: " <> description <> "\nhint: " <> hint
}

pub fn do_read_file(file) {
  simplifile.read(file)
  |> result.map_error(fn(err) { format_file_error(file, err) })
}

@external(javascript, "./system_ffi.mjs", "readStdin")
pub fn read_stdin() -> Result(String, String)
