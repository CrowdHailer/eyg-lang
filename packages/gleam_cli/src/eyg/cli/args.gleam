pub type Args {
  Repl
  Run(file: String)
  Compile(file: String)
  Share(file: String)
  Fetch(cid: String)
  SignatoryInitial(name: String)
  Publish(package: String, file: String)
  Help
  Version
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
    ["help"] | ["--help"] | ["-h"] -> Help
    ["version"] | ["--version"] | ["-V"] -> Version
    _ -> Fail
  }
}

pub const help_text = "eyg — run EYG programs and interact with the EYG hub
usage: eyg [<command> [<args>]]
commands:
  (no args)              start the REPL
  run <file>             run a script (.eyg or .eyg.json)
  compile <file>         compile a script to JavaScript
  share <file>           share an IR module with the hub
  fetch <cid>            fetch a module by content id
  publish <pkg> <file>   publish a module under a package name
  signatory initial <n>  create a signatory principal called <n>
  help, --help, -h       show this message
  version, --version, -V show the eyg version
environment:
  EYG_ORIGIN             override the hub origin (default: https://eyg.run)
"
