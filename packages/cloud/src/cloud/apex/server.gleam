//// One app serves the API and the web interface, see `router` for the routes.

import cloud/apex/access.{type Access}
import cloud/apex/api
import cloud/apex/context.{type Context}
import cloud/apex/router
import gleam/http/request
import gleam/http/response
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
    case
      access.allowed(access, request.get_header(ctx.request, "authorization"))
    {
      True -> next(ctx)
      False ->
        api.status(401)
        |> response.set_header(access.challenge.0, access.challenge.1)
    }
  })
  |> howdy.controller(router.controller(context))
}
