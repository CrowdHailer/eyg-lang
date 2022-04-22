import eyg/typer/polytype

// Harness is the connection between the world/environment/platform & a program
// Program <- Harness -> Platform = Applicatin
// Is this the Harness?
pub type Harness(n) {
  Harness(
    variables: List(#(String, polytype.Polytype(n))),
    native_to_string: fn(n) -> String,
  )
}
