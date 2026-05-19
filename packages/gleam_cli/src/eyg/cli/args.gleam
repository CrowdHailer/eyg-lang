import eyg/cli/internal/source
import gleam/option.{type Option, None, Some}

pub type Args {
  Shell(Option(source.Input))
  Run(input: source.Input)
  Script(input: source.Input, arguments: List(String))
  Eval(input: source.Input)
  Check(input: source.Input)
  Compile(input: source.Input)
  Share(file: String)
  Fetch(cid: String)
  SignatoryInitial(name: String)
  Publish(package: String, file: String)
  Help
  Version
}

pub fn parse(args) {
  case args {
    [] -> Shell(None)
    ["shell", "-c", code] | ["shell", "--code", code] ->
      Shell(Some(source.Code(code)))
    ["shell", "-"] | ["shell", "--stdin"] -> Shell(Some(source.Stdin))
    ["shell", file] -> Shell(Some(source.File(file)))
    ["run", "-c", code] | ["run", "--code", code] -> Run(source.Code(code))
    ["run", "-"] | ["run", "--stdin"] -> Run(source.Stdin)
    ["run", file] -> Run(source.File(file))
    ["eval", "-c", code] | ["eval", "--code", code] -> Eval(source.Code(code))
    ["eval", "-"] | ["eval", "--stdin"] -> Eval(source.Stdin)
    ["eval", file] -> Eval(source.File(file))
    ["script", "-c", code, ..arguments]
    | ["script", "--code", code, ..arguments] ->
      Script(source.Code(code), arguments)
    ["script", "-", ..arguments] | ["script", "--stdin", ..arguments] ->
      Script(source.Stdin, arguments)
    ["script", file, ..arguments] -> Script(source.File(file), arguments)
    ["check", "-c", code] | ["check", "--code", code] ->
      Check(source.Code(code))
    ["check", "-"] | ["check", "--stdin"] -> Check(source.Stdin)
    ["check", file] -> Check(source.File(file))
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
    [file, ..arguments] -> Script(source.File(file), arguments)
  }
}

pub const help_text = "eyg — run EYG programs and interact with the EYG hub
usage: eyg [<command> [<args>]]
commands:
  (no args)              start the REPL
  <file> [args...]       Run a script with the remaining CLI args
  run <file>             run EYG source from file
  run -, --stdin         run EYG source read from stdin
  run -c, --code <code>  run inline EYG source
  eval <file>            evaluate and print an expression with no side effects
  eval -, --stdin        evaluate EYG source read from stdin
  eval -c, --code <code> evaluate inline EYG source with no side effects
  check <file>           type check a script
  check -, --stdin       type check EYG source read from stdin
  check -c, --code <code> type check inline EYG source
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
