import eyg/cli/internal/platform
import gleam/crypto
import gleam/fetch
import gleam/fetchx
import gleam/io
import gleam/javascript/promise.{type Promise}
import gleam/result
import gleam/uri
import midas/effect as e
import shellout

pub fn run(effect) {
  case effect {
    e.Done(value) -> promise.resolve(value)
    e.Fetch(request:, resume:) -> {
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
      run(resume(reply))
    }
    e.Follow(uri:, resume:) -> {
      use reply <- promise.await(do_follow(uri))
      let result = case reply {
        Ok(string) ->
          case uri.parse(string) {
            Ok(uri) -> Ok(uri)
            Error(Nil) -> Error("failed to parse replied uri")
          }
        Error(message) -> Error(message)
      }
      let result =
        result.map_error(result, fn(message) {
          io.println_error(message)
          Nil
        })
      run(resume(result))
    }
    e.StrongRandom(length:, resume:) -> {
      run(resume(Ok(crypto.strong_random_bytes(length))))
    }
    e.Hash(bytes:, algorithm:, resume:) -> {
      let algorithm = case algorithm {
        e.Sha256 -> crypto.Sha256
        _ -> panic as "unsupported algorithm"
      }
      run(resume(Ok(crypto.hash(algorithm, bytes))))
    }

    _ -> {
      panic as "unsupported effect"
    }
  }
}

fn do_follow(uri: uri.Uri) -> Promise(Result(String, String)) {
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

@external(javascript, "./midas_bun_ffi.mjs", "waitForRedirect")
pub fn wait_for_redirect(port: Int) -> Promise(String)
