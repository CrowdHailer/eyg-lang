import gleam/io
import gleam/list
import gleam/javascript/array.{Array}
import magpie/sources/yaml
import magpie/query.{i, s, v}

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

  query.run(
    ["version"],
    [
      #(v("values"), s("version"), v("version")),
      #(v("values"), s("replicaCount"), i(0)),
    ],
    db,
  )
  |> io.debug

  Nil
}
