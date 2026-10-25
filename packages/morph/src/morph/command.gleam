import gleam/string

pub type Failure {
  NoKeyBinding(key: String)
  ActionFailed(action: String)
}

pub fn fail_message(reason) {
  case reason {
    NoKeyBinding(key) -> string.concat(["No action bound for key '", key, "'"])
    ActionFailed(action) ->
      string.concat(["Action ", action, " not possible at this position"])
  }
}
