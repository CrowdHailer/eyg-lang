import argv
import envoy
import eyg/cli/args
import eyg/cli/fetch
import eyg/cli/internal/client
import eyg/cli/run
import eyg/cli/share
import gleam/io
import gleam/javascript/promise
import gleam/result
import ogre/origin

pub fn main() {
  use result <- promise.map(case args.parse(argv.load().arguments) {
    args.Run(file) -> run.execute(file, config())
    args.Share(file:) -> share.execute(file, config())
    args.Fetch(cid:) -> fetch.execute(cid, config())
    args.Fail -> promise.resolve(Error("bad arguments"))
  })
  case result {
    Ok(message) -> io.println(message)
    Error(reason) -> io.println(reason)
  }
}

fn config() {
  let origin =
    envoy.get("EYG_ORIGIN")
    |> result.try(origin.from_string)
    |> result.unwrap(origin.https("eyg.run"))
  client.Client(origin:)
}
