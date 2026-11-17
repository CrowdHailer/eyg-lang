import cloud/apex/context.{type Context}
import cloud/box/controller as boxes
import cloud/sessions/api as sessions
import gleam/http
import gleam/string
import wisp

pub fn route(request: wisp.Request, context: Context) -> wisp.Response {
  use <- wisp.log_request(request)
  case wisp.path_segments(request), request.method {
    ["boxes"], http.Post -> boxes.create(request, context)
    ["boxes", name], http.Get -> boxes.get(name, context)
    ["boxes", name, "files", ..path], method -> {
      let path = "/" <> string.join(path, "/")
      case method {
        http.Get -> boxes.read(name, path, context)
        http.Put -> boxes.write(request, name, path, context)
        http.Delete -> boxes.delete(name, path, context)
        _ -> wisp.method_not_allowed([http.Get, http.Put, http.Delete])
      }
    }
    ["boxes", name, "sessions"], http.Post ->
      sessions.create(request, name, context)
    ["boxes", name, "sessions"], http.Get -> sessions.list(name, context)
    ["sessions", id], http.Get -> sessions.get(id, context)
    ["sessions", id, "events"], http.Get -> sessions.export(id, context)
    ["sessions", id, "turns"], http.Post -> sessions.turn(request, id, context)
    _, _ -> wisp.not_found()
  }
}
