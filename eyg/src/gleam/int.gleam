pub fn to_string(int) {
  do_to_string(int)
}

if erlang {
  external fn do_to_string(Int) -> String =
    "erlang" "integer_to_binary"
}

if javascript {
  external fn do_to_string(Int) -> String =
    "" "Number.prototype.toString.call"

  pub external fn parse(String) -> Int =
    "" "parseInt"
}
