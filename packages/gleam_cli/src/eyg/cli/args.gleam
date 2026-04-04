pub type Args {
  Run(file: String)
  Share(file: String)
  Fetch(cid: String)
  Fail
}

pub fn parse(args) {
  case args {
    ["run", file] -> Run(file:)
    ["share", file] -> Share(file:)
    ["fetch", cid] -> Fetch(cid:)
    _ -> Fail
  }
}
