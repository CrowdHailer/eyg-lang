import gleam/bit_array
import gleam/io
import gleam/list
import gleam/string
import gzlib
import simplifile

pub fn from_commit(root, hash) {
  let base = root <> "/.git"
  let base = case simplifile.read(base) {
    Ok("gitdir: " <> path) ->
      root <> "/" <> string.trim_end(path) <> "/objects/"
    Ok(_) -> panic as "not valid file"
    Error(_) -> base <> "/objects/"
  }

  let assert <<dir:bytes-2, file:bytes>> = bit_array.from_string(hash)

  let assert Ok(object_path) =
    <<base:utf8, dir:bits, "/", file:bits>>
    |> bit_array.to_string

  io.debug(object_path)

  case simplifile.read_bits(object_path) {
    Ok(contents) -> {
      io.debug(contents)
      case
        gzlib.uncompress(contents)
        |> bit_array.to_string
      {
        Ok(text) -> {
          let lines = string.split(text, "\n")
          list.drop_while(lines, fn(l) { l != "" })
          |> string.join("")
          |> io.debug
        }
        Error(reason) -> todo as "not adecoded string"
      }
    }
    Error(reason) -> {
      io.debug(reason)
      todo
    }
  }
}
