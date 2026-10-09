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
import eyg/cli/version
import gleam/result
import loam/platform/computer
import loam/system

pub fn main() {
  start(argv.load().arguments)
  |> system.run
}

/// Run CLI arguments, including output and process exit, through system effects.
pub fn start(arguments: List(String)) -> system.Effect(Nil) {
  use result <- system.then(execute(args.parse(arguments)))
  case result {
    Ok(n) -> system.exit(n)
    Error(reason) -> {
      use Nil <- system.then(system.write_stderr(reason <> "\n"))
      system.exit(1)
    }
  }
}

fn execute(parsed: args.Args) -> system.Effect(Result(Int, String)) {
  case parsed {
    args.Help -> help()
    args.Version -> version()
    args.InvalidArguments(message) -> system.Done(Error(message))

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

fn with_config(parsed) {
  use config <- system.then(config.load())
  use config <- system.try(
    config |> result.replace_error("failed to load config"),
  )
  case parsed {
    args.Help | args.Version | args.InvalidArguments(_) ->
      panic as "handled above"
    args.Shell(input) -> shell.execute(input, config)
    args.Run(input:) -> run.execute(input, config)
    args.Script(input:, arguments:) -> script.execute(input, arguments, config)
    args.Eval(input:) -> eval.execute(input, config)
    args.Check(input:) -> check.execute(input, config)
    args.Compile(input:) -> compile.execute(input, config)
    args.Parse(input:) -> parse.execute(input, config)
    args.Share(input:) -> share.execute(input, config)
    args.Fetch(cid:) -> fetch.execute(cid, config)
    args.Publish(package:, file:) -> publish.execute(package, file, config)
    args.SignatoryInitial(name:) -> signatory.initial(name, config)
    args.SignatoryList -> signatory.list(config)
    args.SignatoryShow(alias:) -> signatory.show(alias, config)
    args.Overlay(input:) -> overlay.execute(input, config, computer.effects())
  }
}
