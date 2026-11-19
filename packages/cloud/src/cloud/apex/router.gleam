import cloud/apex/context.{type Context}
import cloud/box/controller as boxes
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
    _, _ -> wisp.not_found()
  }
}
