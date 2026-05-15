import eyg/cli/internal/source

pub type Args {
  Repl
  Run(input: source.Input)
  Eval(input: source.Input)
  Compile(input: source.Input)
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
    ["run", "-c", code] | ["run", "--code", code] -> Run(source.Code(code))
    ["run", "-"] | ["run", "--stdin"] -> Run(source.Stdin)
    ["run", file] -> Run(source.File(file))
    ["eval", "-c", code] | ["eval", "--code", code] -> Eval(source.Code(code))
    ["eval", "-"] | ["eval", "--stdin"] -> Eval(source.Stdin)
    ["eval", file] -> Eval(source.File(file))
    ["compile", "-c", code] | ["compile", "--code", code] ->
      Compile(source.Code(code))
    ["compile", "-"] | ["compile", "--stdin"] -> Compile(source.Stdin)
    ["compile", file] -> Compile(source.File(file))
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
  run <file>             run a script
  run -, --stdin         run EYG source read from stdin
  run -c, --code <code>  run inline EYG source
  eval <file>            evaluate and print an expression with no side effects
  eval -, --stdin        evaluate EYG source read from stdin
  eval -c, --code <code> evaluate inline EYG source with no side effects
  compile <file>         compile a script to JavaScript
  compile -, --stdin     compile EYG source read from stdin
  compile -c, --code <code>
                         compile inline EYG source to JavaScript
  share <file>           share an IR module with the hub
  fetch <cid>            fetch a module by content id
  publish <pkg> <file>   publish a module under a package name
  signatory initial <n>  create a signatory principal called <n>
  help, --help, -h       show this message
  version, --version, -V show the eyg version
environment:
  EYG_ORIGIN             override the hub origin (default: https://eyg.run)
"
