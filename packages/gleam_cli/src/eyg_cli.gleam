import argv
import eyg/cli/args
import eyg/cli/check
import eyg/cli/compile
import eyg/cli/eval
import eyg/cli/fetch
import eyg/cli/internal/config
import eyg/cli/publish
import eyg/cli/run
import eyg/cli/script
import eyg/cli/share
import eyg/cli/shell
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
    Ok(n) -> shellout.exit(n)
    Error(reason) -> {
      io.println_error(reason)
      shellout.exit(1)
    }
  }
}

fn execute(parsed: args.Args) -> Promise(Result(Int, String)) {
  case parsed {
    args.Help -> help()
    args.Version -> version()

    _ -> with_config(parsed)
  }
}

fn help() {
  io.println(args.help_text)
  promise.resolve(Ok(0))
}

fn version() {
  io.println("eyg " <> version.string)
  promise.resolve(Ok(0))
}

fn with_config(parsed) {
  use config <- promisex.try_sync(
    config.load() |> result.replace_error("failed to load config"),
  )
  case parsed {
    args.Help | args.Version -> panic as "handled above"
    args.Shell(input) -> shell.execute(input, config)
    args.Run(input:) -> run.execute(input, config)
    args.Script(input:, arguments:) -> script.execute(input, arguments, config)
    args.Eval(input:) -> eval.execute(input, config)
    args.Check(input:) -> check.execute(input, config)
    args.Compile(input:) -> compile.execute(input, config)
    args.Share(file:) -> share.execute(file, config)
    args.Fetch(cid:) -> fetch.execute(cid, config)
    args.Publish(package:, file:) -> publish.execute(package, file, config)
    args.SignatoryInitial(name:) -> signatory.initial(name, config)
  }
}
