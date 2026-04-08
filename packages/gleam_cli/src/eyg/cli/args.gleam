pub type Args {
  Run(file: String)
  Share(file: String)
  Fetch(cid: String)
  SignatoryInitial(name: String)
  Publish(package: String, file: String)
  Fail
}

pub fn parse(args) {
  case args {
    ["run", file] -> Run(file:)
    ["share", file] -> Share(file:)
    ["fetch", cid] -> Fetch(cid:)
    ["publish", package, file] -> Publish(package:, file:)
    ["signatory", "initial", name] -> SignatoryInitial(name:)
    _ -> Fail
  }
}
