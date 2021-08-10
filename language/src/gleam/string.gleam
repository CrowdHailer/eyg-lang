if javascript {
  pub external fn concat(List(String)) -> String =
    "../helpers.js" "concat"
}

if erlang {
  pub external fn concat(List(String)) -> String =
    "unicode" "characters_to_binary"
}
