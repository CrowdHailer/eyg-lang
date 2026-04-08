import argv
import eyg/cli/args
import eyg/cli/fetch
import eyg/cli/internal/config
import eyg/cli/publish
import eyg/cli/run
import eyg/cli/share
import eyg/cli/signatory
import gleam/io
import gleam/javascript/promise
import gleam/javascript/promisex
import gleam/result

pub fn main() {
  use result <- promise.map({
    use config <- promisex.try_sync(
      config.load() |> result.replace_error("failed to load config"),
    )
    case args.parse(argv.load().arguments) {
      args.Run(file) -> run.execute(file, config)
      args.Share(file:) -> share.execute(file, config)
      args.Fetch(cid:) -> fetch.execute(cid, config)
      args.Publish(package:, file:) -> publish.execute(package, file, config)
      args.SignatoryInitial(name:) -> signatory.initial(name, config)
      args.Fail -> promise.resolve(Error("bad arguments"))
    }
  })
  case result {
    Ok(message) -> io.println(message)
    Error(reason) -> io.println(reason)
  }
}
