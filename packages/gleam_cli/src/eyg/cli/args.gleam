import gleam/int
import gleam/option.{type Option, None, Some}
import loam/source

pub type Args {
  Shell(Option(source.Input))
  Tui(Option(source.Input))
  Run(input: source.Input)
  Profile(input: source.Input)
  Script(input: source.Input, arguments: List(String))
  Eval(input: source.Input)
  Check(input: source.Input)
  Compile(input: source.Input)
  Parse(input: source.Input)
  Share(input: source.Input)
  Fetch(cid: String)
  SignatoryInitial(name: String)
  SignatoryList
  SignatoryShow(alias: String)
  Publish(package: String, file: String)
  Overlay(input: source.Input)
  Record(input: source.Input, arguments: Option(List(String)))
  RecordShell
  Replay(path: String)
  Inspect(path: String, step: Option(Int))
  Upload(path: String)
  InvalidArguments(message: String)
  Help
  Version
}

pub fn parse(args) {
  case args {
    ["record", "shell"] -> RecordShell
    ["record", "run", "-c", code] | ["record", "run", "--code", code] ->
      Record(source.Code(code), None)
    ["record", "run", "-"] | ["record", "run", "--stdin"] ->
      Record(source.Stdin, None)
    ["record", "run", file] -> Record(source.File(file), None)
    ["record", "script", "-c", code, ..arguments]
    | ["record", "script", "--code", code, ..arguments] ->
      Record(source.Code(code), Some(arguments))
    ["record", "script", "-", ..arguments]
    | ["record", "script", "--stdin", ..arguments] ->
      Record(source.Stdin, Some(arguments))
    ["record", "script", file, ..arguments] ->
      Record(source.File(file), Some(arguments))
    ["record", "-c", code] | ["record", "--code", code] ->
      Record(source.Code(code), None)
    ["record", "-"] | ["record", "--stdin"] -> Record(source.Stdin, None)
    ["record", "#" <> _ as code] | ["record", "@" <> _ as code] ->
      Record(source.Code(code), None)
    ["record", file, ..arguments] -> Record(source.File(file), Some(arguments))
    ["record", ..] ->
      InvalidArguments(
        "usage: eyg record <file> | eyg record -c <code> | eyg record script <file> [args...]",
      )
    ["replay", path] -> Replay(path)
    ["upload", path] -> Upload(path)
    ["inspect", path] -> Inspect(path, None)
    ["inspect", path, step] ->
      case int.parse(step) {
        Ok(step) if step >= 0 -> Inspect(path, Some(step))
        _ -> InvalidArguments("inspect step must be a nonnegative integer")
      }
    [] -> Shell(None)
    ["shell", "-c", code] | ["shell", "--code", code] ->
      Shell(Some(source.Code(code)))
    ["shell", "-"] | ["shell", "--stdin"] -> Shell(Some(source.Stdin))
    ["shell", "#" <> _ as code] | ["shell", "@" <> _ as code] ->
      Shell(Some(source.Code(code)))
    ["shell", file] -> Shell(Some(source.File(file)))
    ["tui"] -> Tui(None)
    ["tui", "-c", code] | ["tui", "--code", code] ->
      Tui(Some(source.Code(code)))
    ["tui", "-"] | ["tui", "--stdin"] -> Tui(Some(source.Stdin))
    ["tui", "#" <> _ as code] | ["tui", "@" <> _ as code] ->
      Tui(Some(source.Code(code)))
    ["tui", file] -> Tui(Some(source.File(file)))
    ["run", "-c", code] | ["run", "--code", code] -> Run(source.Code(code))
    ["run", "-"] | ["run", "--stdin"] -> Run(source.Stdin)
    ["run", "#" <> _ as code] | ["run", "@" <> _ as code] ->
      Run(source.Code(code))
    ["run", file] -> Run(source.File(file))
    ["profile", "-c", code] | ["profile", "--code", code] ->
      Profile(source.Code(code))
    ["profile", "-"] | ["profile", "--stdin"] -> Profile(source.Stdin)
    ["profile", "#" <> _ as code] | ["profile", "@" <> _ as code] ->
      Profile(source.Code(code))
    ["profile", file] -> Profile(source.File(file))
    ["profile", ..] ->
      InvalidArguments(
        "usage: eyg profile <file> | eyg profile -c <code> | eyg profile -",
      )
    ["eval", "-c", code] | ["eval", "--code", code] -> Eval(source.Code(code))
    ["eval", "-"] | ["eval", "--stdin"] -> Eval(source.Stdin)
    ["eval", "#" <> _ as code] | ["eval", "@" <> _ as code] ->
      Eval(source.Code(code))
    ["eval", file] -> Eval(source.File(file))
    ["script", "-c", code, ..arguments]
    | ["script", "--code", code, ..arguments] ->
      Script(source.Code(code), arguments)
    ["script", "-", ..arguments] | ["script", "--stdin", ..arguments] ->
      Script(source.Stdin, arguments)
    ["script", "#" <> _ as code, ..arguments]
    | ["script", "@" <> _ as code, ..arguments] ->
      Script(source.Code(code), arguments)
    ["script", file, ..arguments] -> Script(source.File(file), arguments)
    ["check", "-c", code] | ["check", "--code", code] ->
      Check(source.Code(code))
    ["check", "-"] | ["check", "--stdin"] -> Check(source.Stdin)
    ["check", "#" <> _ as code] | ["check", "@" <> _ as code] ->
      Check(source.Code(code))
    ["check", file] -> Check(source.File(file))
    ["compile", "-c", code] | ["compile", "--code", code] ->
      Compile(source.Code(code))
    ["compile", "-"] | ["compile", "--stdin"] -> Compile(source.Stdin)
    ["compile", "#" <> _ as code] | ["compile", "@" <> _ as code] ->
      Compile(source.Code(code))
    ["compile", file] -> Compile(source.File(file))
    ["parse", "-c", code] | ["parse", "--code", code] ->
      Parse(source.Code(code))
    ["parse", "-"] | ["parse", "--stdin"] -> Parse(source.Stdin)
    ["parse", "#" <> _ as code] | ["parse", "@" <> _ as code] ->
      Parse(source.Code(code))
    ["parse", file] -> Parse(source.File(file))
    ["share", "-c", code] | ["share", "--code", code] ->
      Share(source.Code(code))
    ["share", "-"] | ["share", "--stdin"] -> Share(source.Stdin)
    ["share", file] -> Share(source.File(file))
    ["fetch", cid] -> Fetch(cid:)
    ["publish", package, file] -> Publish(package:, file:)
    ["signatory", "initial", name] -> SignatoryInitial(name:)
    ["signatory", "list"] -> SignatoryList
    ["signatory", "show", alias] -> SignatoryShow(alias:)
    ["signatory", ..] ->
      InvalidArguments(
        "usage: eyg signatory initial <name> | eyg signatory list | eyg signatory show <name>",
      )
    ["overlay"] | ["overlay", "--help"] | ["overlay", "-h"] ->
      InvalidArguments(
        "usage: eyg overlay <file> | eyg overlay -c <code> | eyg overlay -",
      )
    ["overlay", "-c", code] | ["overlay", "--code", code] ->
      Overlay(source.Code(code))
    ["overlay", "-"] | ["overlay", "--stdin"] -> Overlay(source.Stdin)
    ["overlay", file] -> Overlay(source.File(file))
    // overlay doesn't support using a release or content reference as auth should not be included
    ["help"] | ["--help"] | ["-h"] -> Help
    ["version"] | ["--version"] | ["-V"] -> Version
    ["#" <> _ as code, ..arguments] | ["@" <> _ as code, ..arguments] ->
      Script(source.Code(code), arguments)
    [file, ..arguments] -> Script(source.File(file), arguments)
  }
}

pub const help_text =
  "eyg — run EYG programs and interact with the EYG hub
usage: eyg [<command> [<args>]]
commands:
  (no args)              start the shell
  shell <file>           start a shell with the file as shell config
  shell #<mod>, @<pkg>   start a shell with a module or package as shell config
  shell -, --stdin       start a shell with stdin as shell config
  shell -c, --code <code>start a shell with inline shell config
  tui                    start the tui
  tui <file>             start a tui with the file as shell config
  tui #<mod>, @<pkg>     start a tui with a module or package as shell config
  tui -, --stdin         start a tui with stdin as shell config
  tui -c, --code <code>  start a tui with inline shell config
  script <file>          run the script from the provided file
  script -, --stdin      run a script read from stdin
  script -c, --code <code>
  script #<mod>, @<pkg>  run a script from a module or package
                         run a script from inline source
  <file> [args...]       run a script with the remaining CLI args
  #<cid> [args...]       run a script fetched by content id
  @<pkg> [args...]       run a script from a published package
  eval <file>            evaluate and print an expression with no side effects
  eval -, --stdin        evaluate EYG source read from stdin
  eval -c, --code <code> evaluate inline EYG source with no side effects
  eval #<mod>, @<pkg>    evaluate a module or package
  check <file>           type check a script
  check -, --stdin       type check EYG source read from stdin
  check -c, --code <code>type check inline EYG source
  check #<mod>, @<pkg>   type check a module or package
  run <file>             run EYG source from file
  run -, --stdin         run EYG source read from stdin
  run -c, --code <code>  run inline EYG source
  run #<mod>, @<pkg>     run a module or package
  profile <file>         run with named function/effect spans
  record run <file>      run a block and save a portable trajectory
  record run -c <code>   record an inline block
  record <file> [args]   record a script and its arguments
  record shell          record successive shell inputs
  replay <trace>        replay EYG journals from a portable archive
  inspect <trace> [step] show recorded effects and observed file changes
  upload <trace>        send archived spans to Langfuse or an OTLP collector
  profile -c <code>, -   profile inline source or stdin
  compile <file>         compile a script to JavaScript
  compile -, --stdin     compile EYG source read from stdin
  compile -c, --code <code>
                         compile inline EYG source to JavaScript
  compile #<mod>, @<pkg> Compile a module or package to JavaScript
  parse <file>           parse EYG source from file and write JSON to stdout
  parse -, --stdin       parse EYG source read from stdin and write JSON to stdout
  parse -c, --code <code>parse inline EYG source and write JSON to stdout
  parse #<mod>, @<pkg>   parse a module or package and write JSON to stdout
  share <file>           share EYG source from file
  share -, --stdin       share EYG source read from stdin
  share -c, --code <code>share inline EYG source
  fetch <cid>            fetch a module by content id
  publish <pkg> <file>   publish a module under a package name
  signatory initial <n>  create a signatory principal called <n>
  signatory list         list local signatory metadata and current hub status
  signatory show <name>  show signatory metadata and complete hub event history
  overlay <file>         start an overlay session with config file
  overlay -, --stdin     start an overlay session with config from stdin
  overlay -c, --code <code>
                         start an overlay session with inline config
  help, --help, -h       show this message
  version, --version, -V show the eyg version
environment:
  EYG_ORIGIN             override the hub origin (default: https://eyg.run)
  EYG_PROFILE_FILE       write a local Chrome trace JSON recording
  OTEL_EXPORTER_OTLP_ENDPOINT
                         export spans to an OTLP/HTTP base URL
"
