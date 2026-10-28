import envoy
import filepath
import gleam/crypto as gcrypto
import gleam/dynamic.{type Dynamic}
import gleam/fetch
import gleam/fetchx
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/option.{type Option}
import gleam/result
import gleam/time/timestamp
import kryptos/eddsa
import loam/internal/crypto
import loam/internal/prompt
import loam/internal/tracing
import midas/effect
import plinthx/javascript/promise as native_promise
import plinthx/javascript/string as native_string
import shellout
import simplifile
import untethered/keypair

pub type Metadata {
  Metadata(kind: simplifile.FileType, size: Int)
}

// This exists for testing as the runner can be defined straight away.
pub type Effect(a) {
  Done(a)
  SpanStart(String, List(#(String, String)), fn(Nil) -> Effect(a))
  SpanEnd(Option(String), fn(Nil) -> Effect(a))
  AppendFileBits(
    String,
    BitArray,
    fn(Result(Nil, simplifile.FileError)) -> Effect(a),
  )
  CreateDirectory(String, fn(Result(Nil, String)) -> Effect(a))
  Cwd(fn(Result(String, String)) -> Effect(a))
  DeleteFile(String, fn(Result(Nil, simplifile.FileError)) -> Effect(a))
  Env(String, fn(Option(String)) -> Effect(a))
  Exit(Int)
  FileInfo(String, fn(Result(Metadata, simplifile.FileError)) -> Effect(a))
  Fetch(
    Request(BitArray),
    fn(Result(Response(BitArray), effect.FetchError)) -> Effect(a),
  )
  GenerateKey(
    fn(keypair.Keypair(eddsa.PrivateKey, eddsa.PublicKey)) -> Effect(a),
  )
  Hash(effect.HashAlgorithm, BitArray, fn(BitArray) -> Effect(a))
  Now(fn(Int) -> Effect(a))
  Prompt(String, fn(Result(String, Nil)) -> Effect(a))
  Random(Int, fn(Int) -> Effect(a))
  ReadDirectory(
    String,
    fn(Result(List(String), simplifile.FileError)) -> Effect(a),
  )
  ReadFile(String, fn(Result(String, String)) -> Effect(a))
  ReadFileRange(
    path: String,
    offset: Int,
    limit: Int,
    resume: fn(Result(BitArray, simplifile.FileError)) -> Effect(a),
  )
  SetPermissions(String, Int, fn(Result(Nil, String)) -> Effect(a))
  Stdin(fn(Result(String, String)) -> Effect(a))
  Stdout(String, fn(Nil) -> Effect(a))
  Wait(Int, fn(Nil) -> Effect(a))
  WriteFile(String, String, fn(Result(Nil, String)) -> Effect(a))
  WriteFileBits(
    String,
    BitArray,
    fn(Result(Nil, simplifile.FileError)) -> Effect(a),
  )
  WriteStdout(String, fn(Nil) -> Effect(a))
  WriteStderr(String, fn(Nil) -> Effect(a))
}

pub fn append_file_bits(path, contents) {
  AppendFileBits(path, contents, Done)
}

pub fn delete_file(path) {
  DeleteFile(path, Done)
}

pub fn env(name) {
  Env(name, Done)
}

pub fn exit(status) {
  Exit(status)
}

pub fn file_info(path) {
  FileInfo(path, Done)
}

pub fn now() {
  Now(Done)
}

pub fn random(max) {
  Random(max, Done)
}

/// Read up to `limit` bytes at a byte offset. EOF returns an empty array;
/// negative offsets or limits return `Einval` when the effect runs.
pub fn read_file_range(path, offset, limit) {
  ReadFileRange(path, offset, limit, Done)
}

pub fn write_file_bits(path, contents) {
  WriteFileBits(path, contents, Done)
}

/// Write exact text without adding a newline.
pub fn write_stdout(text) {
  WriteStdout(text, Done)
}

/// Write exact text to standard error without adding a newline.
pub fn write_stderr(text) {
  WriteStderr(text, Done)
}

pub fn wait(milliseconds) {
  Wait(milliseconds, Done)
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

pub fn cwd() {
  Cwd(Done)
}

pub fn resolve_relative(root, relative) {
  let joined = case filepath.is_absolute(relative) {
    True -> relative
    False -> filepath.join(root, relative)
  }
  filepath.expand(joined)
  |> result.replace_error(simplifile.Einval)
}

pub fn hash(algorithm, bytes) {
  Hash(algorithm, bytes, Done)
}

pub fn read_directory(path) {
  ReadDirectory(path, Done)
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

/// Display a prompt without a newline and read interactive terminal input.
/// Unlike `stdin`, this does not wait for the entire input stream to end.
/// The driver strips trailing newlines; EOF returns `Ok("")`.
pub fn prompt(text: String) -> Effect(Result(String, Nil)) {
  Prompt(text, Done)
}

/// Print a line, including a trailing newline.
pub fn stdout(text) {
  Stdout(text, Done)
}

pub fn then(effect: Effect(a), func: fn(a) -> Effect(b)) -> Effect(b) {
  case effect {
    Done(value) -> func(value)
    SpanStart(name, attributes, resume) ->
      SpanStart(name, attributes, fn(value) { then(resume(value), func) })
    SpanEnd(error, resume) ->
      SpanEnd(error, fn(value) { then(resume(value), func) })
    Exit(status) -> Exit(status)
    AppendFileBits(path, bytes, resume) ->
      AppendFileBits(path, bytes, fn(result) { then(resume(result), func) })
    DeleteFile(path, resume) ->
      DeleteFile(path, fn(result) { then(resume(result), func) })
    Env(name, resume) -> Env(name, fn(value) { then(resume(value), func) })
    FileInfo(path, resume) ->
      FileInfo(path, fn(result) { then(resume(result), func) })
    Now(resume) -> Now(fn(value) { then(resume(value), func) })
    Prompt(text, resume) ->
      Prompt(text, fn(value) { then(resume(value), func) })
    Random(max, resume) -> Random(max, fn(value) { then(resume(value), func) })
    ReadFileRange(path, offset, limit, resume) ->
      ReadFileRange(path, offset, limit, fn(result) {
        then(resume(result), func)
      })
    WriteFileBits(path, bytes, resume) ->
      WriteFileBits(path, bytes, fn(result) { then(resume(result), func) })
    WriteStdout(text, resume) ->
      WriteStdout(text, fn(value) { then(resume(value), func) })
    WriteStderr(text, resume) ->
      WriteStderr(text, fn(value) { then(resume(value), func) })
    GenerateKey(resume) ->
      GenerateKey(fn(keypair) { then(resume(keypair), func) })
    Fetch(request, resume) ->
      Fetch(request, fn(response) { then(resume(response), func) })
    CreateDirectory(path, resume) ->
      CreateDirectory(path, fn(response) { then(resume(response), func) })
    Cwd(resume) -> Cwd(fn(response) { then(resume(response), func) })
    Hash(algorithm, bytes, resume) ->
      Hash(algorithm, bytes, fn(output) { then(resume(output), func) })
    ReadDirectory(path, resume) ->
      ReadDirectory(path, fn(response) { then(resume(response), func) })
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

pub fn map(effect: Effect(a), func: fn(a) -> b) -> Effect(b) {
  then(effect, fn(value) { Done(func(value)) })
}

pub fn traverse(items: List(a), func: fn(a) -> Effect(b)) -> Effect(List(b)) {
  case items {
    [] -> Done([])
    [item, ..rest] -> {
      use value <- then(func(item))
      use values <- map(traverse(rest, func))
      [value, ..values]
    }
  }
}

/// Reduce a list of items into a single value by applying an accumulator and each item an effectful function.
pub fn fold(items: List(a), acc: b, func: fn(b, a) -> Effect(b)) -> Effect(b) {
  case items {
    [] -> Done(acc)
    [item, ..rest] -> {
      use acc <- then(func(acc, item))
      fold(rest, acc, func)
    }
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

/// Trace a lazy workflow, ending the span before its caller resumes.
/// The error callback describes operational failure, not application quality.
pub fn span(
  name: String,
  attributes: List(#(String, String)),
  work: fn() -> Effect(a),
  error: fn(a) -> Option(String),
) -> Effect(a) {
  use Nil <- then(SpanStart(name, attributes, Done))
  use value <- then(work())
  use Nil <- map(SpanEnd(error(value), Done))
  value
}

pub fn run(effect: Effect(a)) -> Promise(a) {
  run_traced(effect, tracing.new())
}

/// Explicit per-run configuration, useful for hosts that do not have process env.
pub fn run_with_environment(
  effect: Effect(a),
  env: List(#(String, String)),
) -> Promise(a) {
  run_traced(effect, tracing.configured(env))
}

fn run_traced(effect: Effect(a), trace: tracing.Context) -> Promise(a) {
  use #(outcome, trace) <- promise.await(run_effect(fn() { effect }, trace))
  let error = case outcome {
    Ok(_) -> option.None
    Error(reason) ->
      option.Some(native_string.from(reason) |> result.unwrap("host exception"))
  }
  use Nil <- promise.await(tracing.finish(trace, error))
  case outcome {
    Ok(value) -> promise.resolve(value)
    Error(reason) -> {
      let assert Ok(constructor) = native_promise.get()
      native_promise.reject(constructor, reason)
    }
  }
}

type Driver(a) {
  Finished(a, tracing.Context)
  NextEffect(fn() -> Effect(a), tracing.Context)
}

fn run_effect(
  work: fn() -> Effect(a),
  trace: tracing.Context,
) -> Promise(#(Result(a, Dynamic), tracing.Context)) {
  // Catch one step at a time, releasing its old context before driving the next.
  // Otherwise pending exception handlers retain already-exported span batches.
  use next <- promise.await(
    promise.resolve(Nil)
    |> promise.await(fn(_) { run_step(work(), trace) })
    |> promise.map(Ok)
    |> promise.rescue(Error),
  )
  case next {
    Error(reason) -> promise.resolve(#(Error(reason), trace))
    Ok(Finished(value, trace)) -> promise.resolve(#(Ok(value), trace))
    Ok(NextEffect(work, trace)) -> run_effect(work, trace)
  }
}

fn continue(
  value: value,
  resume: fn(value) -> Effect(a),
  trace: tracing.Context,
) -> Promise(Driver(a)) {
  promise.resolve(NextEffect(fn() { resume(value) }, trace))
}

fn run_step(effect: Effect(a), trace: tracing.Context) -> Promise(Driver(a)) {
  case effect {
    Done(value) -> promise.resolve(Finished(value, trace))
    SpanStart(name, attributes, resume) -> {
      let trace = tracing.start_span(trace, name, attributes)
      continue(Nil, resume, trace)
    }
    SpanEnd(error, resume) -> {
      use trace <- promise.await(tracing.end_span(trace, error))
      continue(Nil, resume, trace)
    }
    Exit(status) -> {
      let error = case status {
        0 -> option.None
        _ -> option.Some("process exited with status " <> int.to_string(status))
      }
      use Nil <- promise.await(tracing.finish(trace, error))
      shellout.exit(status)
      panic as "the process did not stop"
    }
    AppendFileBits(path, bytes, resume) ->
      continue(simplifile.append_bits(path, bytes), resume, trace)
    DeleteFile(path, resume) -> continue(simplifile.delete(path), resume, trace)
    Env(name, resume) ->
      continue(envoy.get(name) |> option.from_result, resume, trace)
    FileInfo(path, resume) -> {
      let result =
        simplifile.file_info(path)
        |> result.map(fn(info) {
          Metadata(simplifile.file_info_type(info), info.size)
        })
      continue(result, resume, trace)
    }
    Now(resume) -> {
      let #(seconds, nanos) =
        timestamp.system_time() |> timestamp.to_unix_seconds_and_nanoseconds
      continue(seconds * 1000 + nanos / 1_000_000, resume, trace)
    }
    Random(max, resume) -> continue(int.random(max), resume, trace)
    ReadFileRange(path, offset, limit, resume) -> {
      let result = case offset < 0 || limit < 0 {
        True -> Error(simplifile.Einval)
        False -> read_at_offset(path, offset, limit)
      }
      continue(result, resume, trace)
    }
    WriteFileBits(path, bytes, resume) ->
      continue(simplifile.write_bits(path, bytes), resume, trace)
    WriteStdout(text, resume) -> continue(io.print(text), resume, trace)
    WriteStderr(text, resume) -> continue(io.print_error(text), resume, trace)
    GenerateKey(resume) -> continue(crypto.generate_key(), resume, trace)
    Fetch(request, resume) -> {
      use response <- promise.await(do_fetch(request))
      continue(response, resume, trace)
    }
    CreateDirectory(path, resume) ->
      continue(do_create_directory(path), resume, trace)
    Cwd(resume) -> continue(do_cwd(), resume, trace)
    Hash(algorithm, bytes, resume) ->
      continue(do_hash(algorithm, bytes), resume, trace)
    ReadDirectory(path, resume) ->
      continue(simplifile.read_directory(path), resume, trace)
    ReadFile(path, resume) -> continue(do_read_file(path), resume, trace)
    WriteFile(path, contents, resume) ->
      continue(do_write_file(path, contents), resume, trace)
    SetPermissions(path, permissions, resume) ->
      continue(do_set_permissions(path, permissions), resume, trace)
    Stdin(resume) -> continue(read_stdin(), resume, trace)
    Prompt(text, resume) -> {
      use value <- promise.await(prompt.read_line(text))
      continue(value, resume, trace)
    }
    Stdout(text, resume) -> continue(io.println(text), resume, trace)
    Wait(duration, resume) -> {
      use response <- promise.await(promise.wait(duration))
      continue(response, resume, trace)
    }
  }
}

fn do_create_directory(path) {
  simplifile.create_directory_all(path)
  |> result.map_error(simplifile.describe_error)
}

fn do_cwd() {
  simplifile.current_directory()
  |> result.map_error(simplifile.describe_error)
}

pub fn do_hash(algorithm, bytes) {
  let algorithm = case algorithm {
    effect.Sha1 -> gcrypto.Sha1
    effect.Sha256 -> gcrypto.Sha256
    effect.Sha384 -> gcrypto.Sha384
    effect.Sha512 -> gcrypto.Sha512
  }
  gcrypto.hash(algorithm, bytes)
}

fn do_fetch(request) {
  use response <- promise.map(fetchx.send_bits(request))
  result.map_error(response, fn(reason) {
    case reason {
      fetch.NetworkError(reason) -> effect.NetworkError(reason)
      fetch.UnableToReadBody | fetch.InvalidJsonBody -> effect.UnableToReadBody
    }
  })
}

fn do_write_file(path, contents) {
  simplifile.write(path, contents)
  |> result.map_error(simplifile.describe_error)
}

fn do_set_permissions(path, permissions) {
  simplifile.set_permissions_octal(path, permissions)
  |> result.map_error(simplifile.describe_error)
}

pub fn format_file_error(path: String, err: simplifile.FileError) -> String {
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

fn do_read_file(file) {
  simplifile.read(file)
  |> result.map_error(fn(err) { format_file_error(file, err) })
}

@external(javascript, "./system_ffi.mjs", "readStdin")
pub fn read_stdin() -> Result(String, String)

@external(javascript, "./internal/file_ffi.mjs", "readAtOffset")
fn read_at_offset(
  path: String,
  offset: Int,
  limit: Int,
) -> Result(BitArray, simplifile.FileError)
