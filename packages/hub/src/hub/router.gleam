import gleam/http
import gleam/http/request.{Request}
import hub/registry/controller as registry
import wisp

pub fn route(request, context) {
  let Request(method:, ..) = request
  case request.path_segments(request) {
    ["registry", ..rest] -> {
      case rest, method {
        ["share"], http.Post -> registry.share(request, context)
        ["modules", cid], http.Get -> registry.module(cid, context)
        // ["submit"], http.Post -> registry.submit(request, context)
        // ["entries"], http.Get -> registry.entries(request, context)
        // List packes
        // ["packages"], http.Get -> registry.packages(context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    _ -> wisp.html_response("Nothing", 404)
  }
}
