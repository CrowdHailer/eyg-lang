import eyg/typer/polytype

// Harness is the connection between the world/environment & a program
// Is this the Harness?
pub type Harness(n) {
  Harness(
    variables: List(#(String, polytype.Polytype(n))),
    native_to_string: fn(n) -> String,
  )
}
