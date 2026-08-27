import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/result
import simplifile

// This exists for testing as the runner can be defined straight away.
pub type Effect(a) {
  Done(a)
  ReadFile(String, fn(Result(String, String)) -> Effect(a))
  Stdin(fn(Result(String, String)) -> Effect(a))
  Stdout(String, fn(Nil) -> Effect(a))
}

pub fn read_file(path) {
  ReadFile(path, Done)
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
    ReadFile(path, resume) ->
      ReadFile(path, fn(response) { then(resume(response), func) })
    Stdin(resume) -> Stdin(fn(response) { then(resume(response), func) })
    Stdout(text, resume) ->
      Stdout(text, fn(response) { then(resume(response), func) })
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
    ReadFile(path, resume) -> run(resume(do_read_file(path)))
    Stdin(resume) -> run(resume(read_stdin()))
    Stdout(text, resume) -> run(resume(io.println(text)))
  }
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
