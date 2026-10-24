import argv
import eyg/cli/args
import eyg/cli/check
import eyg/cli/compile
import eyg/cli/eval
import eyg/cli/fetch
import eyg/cli/internal/config
import eyg/cli/overlay
import eyg/cli/parse
import eyg/cli/publish
import eyg/cli/run
import eyg/cli/script
import eyg/cli/share
import eyg/cli/shell
import eyg/cli/signatory
import eyg/cli/tui
import eyg/cli/version
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/result
import loam/system

pub fn main() -> promise.Promise(Nil) {
  start(argv.load().arguments)
}

/// Run CLI arguments, including output and process exit, through system effects.
pub fn start(arguments: List(String)) -> promise.Promise(Nil) {
  use result <- promise.await(execute(args.parse(arguments)))
  case result {
    Ok(n) -> system.exit(n)
    Error(reason) -> {
      use Nil <- system.then(system.write_stderr(reason <> "\n"))
      system.exit(1)
    }
  }
  |> system.run
}

fn execute(parsed: args.Args) -> promise.Promise(Result(Int, String)) {
  case parsed {
    args.Help -> help() |> system.run()
    args.Version -> version() |> system.run()
    args.InvalidArguments(message) ->
      system.Done(Error(message)) |> system.run()

    _ -> with_config(parsed)
  }
}

fn help() {
  use Nil <- system.map(system.stdout(args.help_text))
  Ok(0)
}

fn version() {
  use Nil <- system.map(system.stdout("eyg " <> version.string()))
  Ok(0)
}

fn with_config(parsed: args.Args) -> promise.Promise(Result(Int, String)) {
  use config <- promise.await(config.load() |> system.run())
  use config <- promisex.try_sync(
    config |> result.replace_error("failed to load config"),
  )
  case parsed {
    args.Help | args.Version | args.InvalidArguments(_) ->
      panic as "handled above"
    args.Shell(input) -> shell.execute(input, config) |> system.run()
    args.Tui(input) -> tui.execute(input, config)
    args.Run(input:) -> run.execute(input, config) |> system.run()
    args.Script(input:, arguments:) ->
      script.execute(input, arguments, config) |> system.run()
    args.Eval(input:) -> eval.execute(input, config) |> system.run()
    args.Check(input:) -> check.execute(input, config) |> system.run()
    args.Compile(input:) -> compile.execute(input, config) |> system.run()
    args.Parse(input:) -> parse.execute(input, config) |> system.run()
    args.Share(input:) -> share.execute(input, config) |> system.run()
    args.Fetch(cid:) -> fetch.execute(cid, config) |> system.run()
    args.Publish(package:, file:) ->
      publish.execute(package, file, config) |> system.run()
    args.SignatoryInitial(name:) ->
      signatory.initial(name, config) |> system.run()
    args.SignatoryList -> signatory.list(config) |> system.run()
    args.SignatoryShow(alias:) -> signatory.show(alias, config) |> system.run()
    args.Overlay(input:) -> overlay.execute(input, config) |> system.run()
  }
}
