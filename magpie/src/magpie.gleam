import gleam/io
import gleam/int
import gleam/list
import gleam/string
import gleam/javascript/array.{Array}
import magpie/sources/yaml
import magpie/query.{i, s, v}
import magpie/store/in_memory.{B, I, L, S}

pub external fn read_dir_sync(String) -> String =
  "fs" "readdirSync"

pub external fn glob(String) -> Array(String) =
  "./magpie_ffi.mjs" "sync"

pub fn main() {
  io.debug("start")
  let db =
    glob("../")
    |> array.to_list
    |> yaml.read_files
  io.debug("db ready")

  // query.run(
  //   ["driver", "version"],
  //   [
  //     #(v("values"), s("driver"), v("driver")),
  //     #(v("values"), s("version"), v("version")),
  //     #(v("values"), s("replicaCount"), i(0)),
  //   ],
  //   db,
  // )
  query.run(
    ["version"],
    [
      #(v("values"), s("version"), v("version")),
      #(v("values"), s("driver"), v("driver")),
    ],
    db,
  )
  // currently not unique
  |> list.unique
  |> print

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
