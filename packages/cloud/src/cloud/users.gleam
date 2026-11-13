//// People who use the cloud's web shell.
////
//// The first person to sign in is the admin. Everyone else chooses one of the shells in `cloud.eyg`.
//// Users are kept in `users.json` in the cloud's data directory, with the token in their cookie.

import filepath
import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/result
import simplifile

pub type User {
  User(name: String, token: String, admin: Bool, shell: String)
}

fn path(directory) {
  filepath.join(directory, "users.json")
}

pub fn read(directory: String) -> Result(List(User), String) {
  case simplifile.read(path(directory)) {
    Ok(content) -> {
      let user = {
        use name <- decode.field("name", decode.string)
        use token <- decode.field("token", decode.string)
        use admin <- decode.field("admin", decode.bool)
        use shell <- decode.optional_field("shell", "", decode.string)
        decode.success(User(name:, token:, admin:, shell:))
      }
      json.parse(content, decode.list(user))
      |> result.replace_error("invalid " <> path(directory))
    }
    Error(simplifile.Enoent) -> Ok([])
    Error(reason) -> Error(simplifile.describe_error(reason))
  }
}

pub fn write(directory: String, users: List(User)) -> Result(Nil, String) {
  let content =
    json.array(users, fn(user) {
      json.object([
        #("name", json.string(user.name)),
        #("token", json.string(user.token)),
        #("admin", json.bool(user.admin)),
        #("shell", json.string(user.shell)),
      ])
    })
    |> json.to_string
  let _ = simplifile.create_directory_all(directory)
  use _ <- result.try(
    simplifile.write(path(directory), content)
    |> result.map_error(simplifile.describe_error),
  )
  simplifile.set_permissions_octal(path(directory), 0o600)
  |> result.map_error(simplifile.describe_error)
}

/// Add a user, the first is the admin. Names are unique.
pub fn add(
  users: List(User),
  name: String,
  token: String,
  shell: String,
) -> Result(#(User, List(User)), String) {
  case name, list.any(users, fn(u) { u.name == name }) {
    "", _ -> Error("enter a name")
    _, True -> Error(name <> " is taken")
    _, False -> {
      let user = User(name:, token:, admin: users == [], shell:)
      Ok(#(user, list.append(users, [user])))
    }
  }
}

pub fn by_token(users: List(User), token: String) -> Result(User, Nil) {
  list.find(users, fn(u) { u.token == token && token != "" })
}
