import gleam/io
import gleam/int
import gleam/list
import gleam/string
import gleam/javascript/array.{type Array}
import plinth/node/fs
import plinth/node/process
import magpie/sources/yaml
import magpie/store/in_memory.{B, I, L, S}
import magpie/store/json
import magpie/sources/movies

// glob is using an external dependency so will not be part of plinth
@external(javascript, "./magpie_ffi.mjs", "sync")
pub fn glob(glob: String) -> Array(String)

// web worker for loading
// boolean and int editing

/// Returns a list containing the command-line arguments passed when the Node.js process was launched.
/// The first element will be `process.execPath`.
/// The second element will be the path to the JavaScript file being executed.
/// The remaining elements will be any additional command-line arguments.
pub fn args() {
  array.to_list(process.argv())
}

pub fn main() {
  io.debug("start")
  let db = case list.drop(args(), 2) {
    ["movies"] -> movies.movies()
    ["fleet"] ->
      // #vvalues,sversion,vversion,r0,sdriver,slitmus:1&vvalues,sdriver,vdriver,r0,sversion,vversion,r0,sreplicaCount,i0:1,2
      glob("../../../northvolt/firefly-release/**/fleet.yaml")
      |> array.to_list
      |> yaml.read_files
    ["system-config"] ->
      glob("../../../northvolt/system-config/nodesets/**/system.yml")
      |> array.to_list
      |> yaml.read_files
    _ -> panic("need an argument when building state")
  }

  let content =
    string.concat([
      "export function data(){\n  return ",
      json.to_string(db.triples),
      "\n}",
    ])
  let assert Ok(Nil) =
    fs.write_file_sync("build/dev/javascript/magpie/db.mjs", content)
  let assert Ok(Nil) =
    fs.write_file_sync("public/db.json", json.to_string(db.triples))
  Nil
}

pub fn print(relations) {
  list.each(relations, fn(relation) {
    relation
    |> list.map(print_value)
    |> string.join(", ")
    |> io.println
  })
}

fn print_value(value) {
  case value {
    B(False) -> "False"
    B(True) -> "True"
    I(i) -> int.to_string(i)
    L(_l) -> "[TODO]"
    S(s) -> string.concat(["\"", s, "\""])
  }
}
