//// Atomic snapshots beneath a session's private directory.

import filepath
import gleam/bit_array
import gleam/crypto
import gleam/result
import simplifile

pub fn directory(data: String, identity: String) -> String {
  let key =
    crypto.hash(crypto.Sha256, <<identity:utf8>>) |> bit_array.base16_encode
  filepath.join(filepath.join(data, "sessions"), key)
}

pub fn write(path: String, content: String) -> Result(Nil, String) {
  use _ <- result.try(
    simplifile.create_directory_all(filepath.directory_name(path))
    |> result.map_error(simplifile.describe_error),
  )
  let temporary = path <> ".tmp"
  use _ <- result.try(
    simplifile.write(temporary, content)
    |> result.map_error(simplifile.describe_error),
  )
  use _ <- result.try(
    simplifile.set_permissions_octal(temporary, 0o600)
    |> result.map_error(simplifile.describe_error),
  )
  simplifile.rename(temporary, path)
  |> result.map_error(simplifile.describe_error)
}
