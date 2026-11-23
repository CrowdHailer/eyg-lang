//// One app serves the API and the web interface, see `router` for the routes.

import cloud/apex/context.{type Context}
import cloud/apex/router
import howdy
import howdy/logger

/// There is no authentication yet so only local connections are accepted.
pub fn supervised(context: Context, port: Int) {
  app(context)
  |> howdy.bind(to: "127.0.0.1")
  |> howdy.listening(on: port)
  |> howdy.supervised
}

pub fn app(context: Context) -> howdy.App {
  howdy.new()
  |> howdy.middleware(logger.log)
  |> howdy.controller(router.controller(context))
}
