pub type Args {
  Run(file: String)
  Fail
}

pub fn parse(args) {
  case args {
    ["run", file] -> Run(file:)
    _ -> Fail
  }
}
