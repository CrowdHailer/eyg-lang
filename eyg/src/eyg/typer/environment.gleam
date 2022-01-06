import eyg/typer/polytype

// Is this the Harness?
pub type Environment(n) {
  Environment(
    variables: List(#(String, polytype.Polytype(n))),
    native_to_string: fn(n) -> String,
  )
}
