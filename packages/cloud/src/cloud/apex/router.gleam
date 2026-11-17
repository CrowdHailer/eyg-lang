import cloud/apex/context.{type Context}
import cloud/box/controller as boxes
import cloud/sessions/api as sessions
import gleam/http
import gleam/string
import wisp

pub fn route(request: wisp.Request, context: Context) -> wisp.Response {
  use <- wisp.log_request(request)
  case wisp.path_segments(request), request.method {
    ["boxes"], http.Get -> boxes.list(context)
    ["boxes"], http.Post -> boxes.create(request, context)
    ["boxes", id], http.Get -> boxes.get(id, context)
    ["boxes", id, "files", ..path], method -> {
      let path = "/" <> string.join(path, "/")
      case method {
        http.Get -> boxes.read(id, path, context)
        http.Put -> boxes.write(request, id, path, context)
        http.Delete -> boxes.delete(id, path, context)
        _ -> wisp.method_not_allowed([http.Get, http.Put, http.Delete])
      }
    }
    ["boxes", id, "secrets"], http.Get -> boxes.secrets(id, context)
    ["boxes", id, "secrets", name], http.Put ->
      boxes.set_secret(request, id, name, context)
    ["boxes", id, "secrets", name], http.Delete ->
      boxes.delete_secret(id, name, context)
    ["boxes", id, "sessions"], http.Post ->
      sessions.create(request, id, context)
    ["boxes", id, "sessions"], http.Get -> sessions.list(id, context)
    ["llms"], http.Get -> sessions.llms(context)
    ["sessions", id], http.Get -> sessions.get(id, context)
    ["sessions", id, "events"], http.Get -> sessions.export(id, context)
    ["sessions", id, "fork"], http.Post -> sessions.fork(id, context)
    ["sessions", id, "trace"], http.Get -> sessions.trace(id, context)
    ["sessions", id, "turns"], http.Post -> sessions.turn(request, id, context)
    _, _ -> wisp.not_found()
  }
}
