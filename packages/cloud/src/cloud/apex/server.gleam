import cloud/apex/access.{type Access}
import cloud/apex/router
import gleam/http/request
import mist
import wisp
import wisp/wisp_mist

pub fn start(context, access: Access, port) {
  wisp.configure_logger()
  handler(context, access)
  // No cookies are set so the secret is never used again.
  |> wisp_mist.handler(wisp.random_string(64))
  |> mist.new
  |> mist.bind(access.bind(access))
  |> mist.port(port)
  |> mist.start
}

/// Requests need the password if there is one, see `access`.
/// `/health` does not, it only says the service is running, for the host's health checks.
pub fn handler(context, access: Access) {
  fn(request: wisp.Request) {
    case
      request.path,
      access.allowed(access, request.get_header(request, "authorization"))
    {
      "/health", _ -> wisp.ok()
      _, True -> router.route(request, context)
      _, False ->
        wisp.response(401)
        |> wisp.set_header(access.challenge.0, access.challenge.1)
    }
  }
}
