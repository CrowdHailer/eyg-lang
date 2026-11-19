import cloud/apex/router
import mist
import wisp
import wisp/wisp_mist

/// There is no authentication yet so only local connections are accepted.
pub fn start(context, port) {
  wisp.configure_logger()
  router.route(_, context)
  // No cookies are set so the secret is never used again.
  |> wisp_mist.handler(wisp.random_string(64))
  |> mist.new
  |> mist.bind("localhost")
  |> mist.port(port)
  |> mist.start
}
