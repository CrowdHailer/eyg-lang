//// People who use the cloud's web shell.
////
//// The first person to sign in is the admin. Everyone else chooses one of the shells in `cloud.eyg`.
//// The registry holds users in memory, with the token in their cookie.

import gleam/list

pub type User {
  User(name: String, token: String, admin: Bool, shell: String)
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
