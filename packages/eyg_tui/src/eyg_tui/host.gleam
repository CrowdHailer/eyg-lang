//// Deliberately limited host: files are read, network and writes return errors.

import envoy
import gleam/float
import gleam/int
import gleam/option
import gleam/result
import gleam/string
import gleam/time/timestamp
import loam/system
import midas/effect
import simplifile

pub fn run(work: system.Effect(a)) -> Result(a, String) {
  case work {
    system.Done(value) -> Ok(value)
    system.Env(name, resume) ->
      run(resume(envoy.get(name) |> option.from_result))
    system.Now(resume) ->
      run(resume(
        timestamp.system_time()
        |> timestamp.to_unix_seconds
        |> fn(seconds) { float.round(seconds *. 1000.0) },
      ))
    system.Random(max, resume) -> run(resume(int.random(max)))
    system.ReadKey(_, resume) -> run(resume(option.None))
    system.Cwd(resume) ->
      run(resume(
        simplifile.current_directory()
        |> result.map_error(simplifile.describe_error),
      ))
    system.ReadFile(path, resume) ->
      run(resume(
        simplifile.read(path)
        |> result.map_error(system.format_file_error(path, _)),
      ))
    system.ReadDirectory(path, resume) ->
      run(resume(simplifile.read_directory(path)))
    system.FileInfo(path, resume) ->
      run(resume(
        simplifile.file_info(path)
        |> result.map(fn(info) {
          system.Metadata(simplifile.file_info_type(info), info.size)
        }),
      ))
    system.Hash(algorithm, bytes, resume) ->
      run(resume(system.do_hash(algorithm, bytes)))
    system.SpanStart(_, _, resume) -> run(resume(Nil))
    system.SpanEnd(_, resume) -> run(resume(Nil))
    system.Fetch(_, resume) ->
      run(resume(Error(effect.NetworkError(unavailable))))
    system.FetchStream(_, resume) ->
      run(resume(Error(effect.NetworkError(unavailable))))
    system.WriteFile(_, _, resume) -> run(resume(Error(unavailable)))
    system.CreateDirectory(_, resume) -> run(resume(Error(unavailable)))
    system.ReadFileRange(path:, resume:, ..) ->
      run(resume(Error(simplifile.Unknown(path <> ": " <> unavailable))))
    system.WriteFileBits(path, _, resume) ->
      run(resume(Error(simplifile.Unknown(path <> ": " <> unavailable))))
    system.AppendFileBits(path, _, resume) ->
      run(resume(Error(simplifile.Unknown(path <> ": " <> unavailable))))
    system.DeleteFile(path, resume) ->
      run(resume(Error(simplifile.Unknown(path <> ": " <> unavailable))))
    _ -> Error(string.inspect(work) |> operation)
  }
}

const unavailable = "This operation needs the JavaScript host"

fn operation(work) {
  let name = case string.split_once(work, "(") {
    Ok(#(name, _)) -> name
    Error(_) -> "Operation"
  }
  name <> ": " <> unavailable
}
