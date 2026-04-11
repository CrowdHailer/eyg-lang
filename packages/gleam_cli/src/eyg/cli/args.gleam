pub type Args {
  Repl
  Run(file: String)
  Compile(file: String)
  Share(file: String)
  Fetch(cid: String)
  SignatoryInitial(name: String)
  Publish(package: String, file: String)
  Fail
}

pub fn parse(args) {
  case args {
    [] -> Repl
    ["run", file] -> Run(file:)
    ["compile", file] -> Compile(file:)
    ["share", file] -> Share(file:)
    ["fetch", cid] -> Fetch(cid:)
    ["publish", package, file] -> Publish(package:, file:)
    ["signatory", "initial", name] -> SignatoryInitial(name:)
    _ -> Fail
  }
}
