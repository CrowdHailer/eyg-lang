import gleam/io
import gleam/int
import gleam/list
import gleam/string
import gleam/javascript/array.{Array}
import magpie/sources/yaml
import magpie/query.{i, s, v}
import magpie/store/in_memory.{B, I, L, S}
import magpie/store/json

pub external fn read_dir_sync(String) -> String =
  "fs" "readdirSync"

pub external fn glob(String) -> Array(String) =
  "./magpie_ffi.mjs" "sync"

external fn write_file_sync(String, String) -> String =
  "fs" "writeFileSync"

pub fn main() {
  io.debug("start")
  let db =
    glob("../../../northvolt/firefly-release/**/fleet.yaml")
    |> array.to_list
    |> yaml.read_files

  let content =
    string.concat([
      "export function data(){\n  return ",
      json.to_string(db.triples),
      "\n}",
    ])
  write_file_sync("build/dev/javascript/magpie/db.mjs", content)
  Nil
}

pub fn print(relations) {
  list.each(
    relations,
    fn(relation) {
      relation
      |> list.map(print_value)
      |> string.join(", ")
      |> io.println
    },
  )
}

fn print_value(value) {
  case value {
    B(False) -> "False"
    B(True) -> "True"
    I(i) -> int.to_string(i)
    L(l) -> "[todo]"
    S(s) -> string.concat(["\"", s, "\""])
  }
}
