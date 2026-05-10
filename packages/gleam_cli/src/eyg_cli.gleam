import argv
import eyg/cli/args
import eyg/cli/compile
import eyg/cli/fetch
import eyg/cli/internal/config
import eyg/cli/publish
import eyg/cli/repl
import eyg/cli/run
import eyg/cli/share
import eyg/cli/signatory
import eyg/cli/version
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/result

pub fn main() {
  use result <- promise.map(execute(args.parse(argv.load().arguments)))
  case result {
    Ok(message) -> io.println(message)
    Error(reason) -> io.println(reason)
  }
}

fn execute(parsed) {
  case parsed {
    args.Help -> promise.resolve(Ok(args.help_text))
    args.Version -> promise.resolve(Ok("eyg " <> version.string))
    args.Fail -> promise.resolve(Error("bad arguments. try `eyg --help`."))
    _ -> with_config(parsed)
  }
}

fn with_config(parsed) {
  use config <- promisex.try_sync(
    config.load() |> result.replace_error("failed to load config"),
  )
  case parsed {
    args.Help | args.Version | args.Fail -> panic as "handled above"
    args.Repl -> repl.execute(config)
    args.Run(file) -> run.execute(file, config)
    args.Compile(file) -> compile.execute(file, config)
    args.Share(file:) -> share.execute(file, config)
    args.Fetch(cid:) -> fetch.execute(cid, config)
    args.Publish(package:, file:) -> publish.execute(package, file, config)
    args.SignatoryInitial(name:) -> signatory.initial(name, config)
  }
}
