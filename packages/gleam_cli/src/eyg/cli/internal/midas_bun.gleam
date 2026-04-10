import gleam/crypto
import gleam/fetch
import gleam/fetchx
import gleam/javascript/promise.{type Promise}
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
      let assert Ok(reply) = uri.parse(reply)
      run(resume(Ok(reply)))
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

fn do_follow(uri) {
  let url = uri.to_string(uri)
  let assert Ok(_) =
    shellout.command(run: "open", with: [url], in: ".", opt: [])
  wait_for_redirect(8080)
}

@external(javascript, "./midas_bun_ffi.mjs", "waitForRedirect")
pub fn wait_for_redirect(port: Int) -> Promise(String)
