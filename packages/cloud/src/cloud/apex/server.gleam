//// One app serves the API, the web interface and artifacts, see `router` for the routes.

import cloud/apex/access.{type Access}
import cloud/apex/api
import cloud/apex/context.{type Context}
import cloud/apex/router
import gleam/http/request
import gleam/http/response
import gleam/string
import howdy
import howdy/controller
import howdy/health
import howdy/logger

pub fn supervised(context: Context, access: Access, port: Int) {
  app(context, access)
  |> howdy.bind(to: access.bind(access))
  |> howdy.listening(on: port)
  |> howdy.supervised
}

/// Requests need the password if there is one, see `access`.
/// `/health` does not, it only says the service is running, for the host's health checks.
pub fn app(context: Context, access: Access) -> howdy.App {
  howdy.new()
  |> howdy.health_check(health.new() |> health.at(path: "/health"))
  |> howdy.middleware(logger.log)
  |> howdy.middleware(fn(ctx: controller.Context, next) {
    let allowed =
      access.allowed(access, request.get_header(ctx.request, "authorization"))
    case allowed, same_origin(ctx.request) {
      True, True -> next(ctx)
      True, False -> api.status(403)
      False, _ ->
        api.status(401)
        |> response.set_header(access.challenge.0, access.challenge.1)
    }
  })
  |> howdy.controller(router.controller(context))
}

// A request with an origin, such as the terminal's socket, comes from a page of this site.
// A page in a sandbox, such as an artifact, has the origin `null`.
fn same_origin(request) {
  case request.get_header(request, "origin") {
    Error(Nil) -> True
    Ok(origin) ->
      case string.split_once(origin, "://") {
        Ok(#(_, host)) -> Ok(host) == request.get_header(request, "host")
        Error(Nil) -> False
      }
  }
}
