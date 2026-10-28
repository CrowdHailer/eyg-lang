//// Everything a session under eval can reach.
////
//// Overlay describes all of its input and output as effect values, so a
//// session can be run against fixtures instead of the world. The environment
//// decides the answer to every request: Overlay's own origin serves guides and
//// the hub, repositories and routes serve other hosts, and any other request
//// is refused unless the network is allowed.

import gleam/http
import gleam/http/request.{type Request}
import gleam/http/response.{type Response}
import gleam/list
import ogre/origin
import overlay/eval/fixture/hub
import overlay/eval/fixture/repository
import overlay/eval/fixture/site

pub type Environment {
  Environment(
    // The origin Overlay is served from, the site and hub answer here.
    origin: origin.Origin,
    site: site.Site,
    hub: hub.Hub,
    repositories: List(repository.Repository),
    routes: List(Route),
    network: Network,
  )
}

/// A fixed response for a request to another service.
pub type Route {
  Route(
    method: http.Method,
    host: String,
    path: String,
    response: Response(BitArray),
  )
}

pub type Network {
  // Requests nothing in the environment answers fail, as if offline.
  Offline
  // Requests nothing in the environment answers are sent to the network.
  Online
}

pub type Answer {
  Answered(Response(BitArray))
  // Only the network can answer.
  Unanswered
  Refused(reason: String)
}

/// An environment with nothing in it, served from `https://eyg.run`.
pub fn empty() -> Environment {
  Environment(
    origin: origin.https("eyg.run"),
    site: site.Site([]),
    hub: hub.new(),
    repositories: [],
    routes: [],
    network: Offline,
  )
}

pub fn route(
  environment: Environment,
  method: http.Method,
  url: String,
  response: Response(BitArray),
) -> Environment {
  let assert Ok(request) = request.to(url)
  let route = Route(method:, host: request.host, path: request.path, response:)
  Environment(..environment, routes: [route, ..environment.routes])
}

/// The answer to a request, from the first part of the environment that serves it.
pub fn answer(environment: Environment, request: Request(BitArray)) -> Answer {
  let own = own_origin(environment.origin, request)
  let answers = [
    fn() {
      case own {
        True -> site.handle(environment.site, request)
        False -> Error(Nil)
      }
    },
    fn() {
      case own {
        True -> hub.handle(environment.hub, request)
        False -> Error(Nil)
      }
    },
    fn() {
      list.find_map(environment.repositories, repository.handle(_, request))
    },
    fn() {
      list.find_map(environment.routes, fn(route) {
        let Route(method:, host:, path:, response:) = route
        case
          method == request.method
          && host == request.host
          && path == request.path
        {
          True -> Ok(response)
          False -> Error(Nil)
        }
      })
    },
  ]
  case list.find_map(answers, fn(answer) { answer() }) {
    Ok(response) -> Answered(response)
    Error(Nil) ->
      case environment.network, own {
        Online, False -> Unanswered
        // Pages of Overlay's own origin are always answered by the fixtures.
        _, True -> Answered(response.new(404) |> response.set_body(<<>>))
        Offline, False ->
          Refused(
            "the eval environment has no network access to "
            <> request.host
            <> request.path,
          )
      }
  }
}

fn own_origin(origin: origin.Origin, request: Request(BitArray)) {
  let origin.Origin(scheme:, host:, port:) = origin
  scheme == request.scheme && host == request.host && port == request.port
}
