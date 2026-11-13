//// The secrets store of a workspace.
////
//// Secrets are kept in `secrets.json` in the workspace's data directory, readable only by its owner.
//// The data directory is `CLOUD_DATA`, or `.data` next to the workspace file, and must not be committed.
//// Secrets are only readable by the workspace configuration, through the `Secret` effect.
//// Channel programs never see a secret's value, see the `secrets` module of the cloud EYG package.
////
//// ```sh
//// gleam run -m cloud/secrets -- set path/to/workspace.eyg OLLAMA_API_KEY < key.txt
//// gleam run -m cloud/secrets -- list path/to/workspace.eyg
//// gleam run -m cloud/secrets -- delete path/to/workspace.eyg OLLAMA_API_KEY
//// ```

import argv
import envoy
import filepath
import gleam/dict.{type Dict}
import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/result
import gleam/string
import simplifile

/// The data directory of the workspace configured by `file`.
pub fn data_directory(file: String) -> String {
  case envoy.get("CLOUD_DATA") {
    Ok(directory) -> directory
    Error(Nil) -> filepath.join(filepath.directory_name(file), ".data")
  }
}

fn path(directory) {
  filepath.join(directory, "secrets.json")
}

pub fn read(directory: String) -> Result(Dict(String, String), String) {
  case simplifile.read(path(directory)) {
    Ok(content) ->
      json.parse(content, decode.dict(decode.string, decode.string))
      |> result.replace_error("invalid " <> path(directory))
    Error(simplifile.Enoent) -> Ok(dict.new())
    Error(reason) -> Error(simplifile.describe_error(reason))
  }
}

pub fn get(directory: String, name: String) -> Result(String, String) {
  use secrets <- result.try(read(directory))
  dict.get(secrets, name) |> result.replace_error("no secret named " <> name)
}

pub fn set(directory: String, name: String, value: String) {
  use secrets <- result.try(read(directory))
  write(directory, dict.insert(secrets, name, value))
}

pub fn delete(directory: String, name: String) {
  use secrets <- result.try(read(directory))
  write(directory, dict.delete(secrets, name))
}

fn write(directory, secrets) {
  let file = path(directory)
  let content =
    secrets
    |> dict.to_list
    |> list.map(fn(pair) { #(pair.0, json.string(pair.1)) })
    |> json.object
    |> json.to_string
  {
    use Nil <- result.try(simplifile.create_directory_all(directory))
    // Create the file empty and restrict it before any secret is written.
    use Nil <- result.try(simplifile.write(file, ""))
    use Nil <- result.try(simplifile.set_permissions_octal(file, 0o600))
    simplifile.write(file, content)
  }
  |> result.map_error(simplifile.describe_error)
}

pub fn main() -> Nil {
  let outcome = case argv.load().arguments {
    ["set", workspace, name] -> {
      let value = string.trim_end(read_stdin())
      set(data_directory(workspace), name, value)
      |> result.replace("Saved " <> name)
    }
    ["delete", workspace, name] ->
      delete(data_directory(workspace), name)
      |> result.replace("Deleted " <> name)
    ["list", workspace] ->
      read(data_directory(workspace))
      |> result.map(fn(secrets) { string.join(dict.keys(secrets), "\n") })
    _ ->
      Error(
        "Usage: gleam run -m cloud/secrets -- set|delete <workspace.eyg> <NAME>
       gleam run -m cloud/secrets -- list <workspace.eyg>
The value to set is read from stdin.",
      )
  }
  case outcome {
    Ok(message) -> io.println(message)
    Error(reason) -> io.println_error(reason)
  }
}

@external(erlang, "cloud_ffi", "read_stdin")
fn read_stdin() -> String
