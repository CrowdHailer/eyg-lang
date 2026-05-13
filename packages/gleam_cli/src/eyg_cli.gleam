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
import gleam/javascript/promise.{type Promise}
import gleam/javascript/promisex
import gleam/result
import shellout

pub fn main() {
  use result <- promise.map(execute(args.parse(argv.load().arguments)))
  case result {
    Ok(_) -> Nil
    Error(reason) -> {
      io.println_error(reason)
      shellout.exit(1)
    }
  }
}

fn execute(parsed: args.Args) -> Promise(Result(Nil, String)) {
  case parsed {
    args.Help -> help()
    args.Version -> version()
    args.Fail -> fail()
    _ -> with_config(parsed)
  }
}

fn help() {
  io.println(args.help_text)
  promise.resolve(Ok(Nil))
}

fn version() {
  io.println("eyg " <> version.string)
  promise.resolve(Ok(Nil))
}

fn fail() {
  io.println("bad arguments. try `eyg --help`.")
  promise.resolve(Ok(Nil))
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
