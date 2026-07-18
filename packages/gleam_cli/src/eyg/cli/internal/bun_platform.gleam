import eyg/cli/internal/platform
import gleam/crypto
import gleam/fetch
import gleam/fetchx
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/javascript/promise.{type Promise}
import gleam/uri.{type Uri}
import midas/continuation
import midas/effect as e
import shellout

pub type Async(t, a) =
  continuation.Continuation(Promise(t), a)

pub fn fetch(
  request: Request(BitArray),
) -> Async(t, Result(Response(BitArray), e.FetchError)) {
  fn(resume) {
    use result <- promise.await(fetchx.send_bits(request))
    let reply = case result {
      Ok(response) -> Ok(response)
      Error(reason) -> {
        let reason = case reason {
          fetch.NetworkError(reason) -> e.NetworkError(reason)
          fetch.UnableToReadBody -> e.UnableToReadBody
          fetch.InvalidJsonBody -> e.UnableToReadBody
        }
        Error(reason)
      }
    }
    resume(reply)
  }
}

pub fn follow(uri: Uri) -> Async(t, Result(Uri, String)) {
  fn(resume) {
    use reply <- promise.await(do_follow(uri))
    let result = case reply {
      Ok(string) ->
        case uri.parse(string) {
          Ok(uri) -> Ok(uri)
          Error(Nil) -> Error("failed to parse replied uri")
        }
      Error(message) -> Error(message)
    }

    resume(result)
  }
}

fn do_follow(uri: Uri) -> Promise(Result(String, String)) {
  let url = uri.to_string(uri)
  // Pick a browser-launch command for the host OS. `open` is the macOS
  // built-in; Linux uses `xdg-open` (or `wslview` on WSL); Windows uses
  // `cmd /c start`. Previously this was hard-coded to `open`, which
  // crashed the OAuth flow on every non-mac platform with a `let_assert`
  // panic on the missing command.
  let #(cmd, args) = case platform.detect_os() {
    platform.Mac -> #("open", [url])
    platform.Linux -> #("xdg-open", [url])
    platform.Windows -> #("cmd", ["/c", "start", "", url])
  }
  let result = shellout.command(run: cmd, with: args, in: ".", opt: [])

  case result {
    Ok(_) -> promise.map(wait_for_redirect(8080), Ok)
    Error(#(_code, output)) -> promise.resolve(Error(output))
  }
}

@external(javascript, "./bun_platform_ffi.mjs", "waitForRedirect")
pub fn wait_for_redirect(port: Int) -> Promise(String)

pub fn hash(algorithm: e.HashAlgorithm, bytes: BitArray) -> Async(t, BitArray) {
  fn(resume) {
    let algorithm = case algorithm {
      e.Sha256 -> crypto.Sha256
      _ -> panic as "unsupported algorithm"
    }
    resume(crypto.hash(algorithm, bytes))
  }
}

pub fn strong_random(length: Int) -> Async(t, BitArray) {
  fn(resume) { resume(crypto.strong_random_bytes(length)) }
}
