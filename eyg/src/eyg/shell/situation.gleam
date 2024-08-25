import gleam/option.{type Option, None}

// connectors make idetity personas.
// situation sitch condition affairs
// locus the effective or perceived location of something abstract.

pub type Situation {
  Situation(netlify: Option(String))
}

pub fn init() {
  Situation(None)
}
