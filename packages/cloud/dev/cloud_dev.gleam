import argv
import cloud/slack/client
import cloud/slack/schema
import envoy
import gleam/httpc
import gleam/io
import gleam/string
import midas/continuation
import midas/effect

pub fn main() {
  do_main(argv.load().arguments)
}

fn do_main(args) {
  case args {
    // check that slack access is available from the env variables.
    ["slack"] -> {
      let assert Ok(token) = envoy.get("SLACK_BOT_TOKEN")
      let context = client.Context(token, fetch)
      case client.auth_test(context)(identity) {
        Ok(schema.Identity(team:, ..)) -> io.println("access to team: " <> team)
        Error(reason) -> io.println_error(string.inspect(reason))
      }
    }
    _ -> io.println("unknown args")
  }
}

fn identity(x) {
  x
}

fn fetch(request) {
  case httpc.send_bits(request) {
    Ok(response) -> continuation.done(response)
    Error(httpc.InvalidUtf8Response) ->
      continuation.fail(effect.UnableToReadBody)
    Error(httpc.FailedToConnect(..)) ->
      continuation.fail(effect.NetworkError("Failed to connect"))
    Error(httpc.ResponseTimeout) ->
      continuation.fail(effect.NetworkError("response timeout"))
  }
}
