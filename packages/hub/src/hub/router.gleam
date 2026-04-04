import gleam/http
import gleam/http/request.{Request}
import hub/modules/controller as modules
import hub/packages/controller as packages
import hub/signatories/controller as signatories
import wisp

pub fn route(request, context) {
  let Request(method:, ..) = request
  case request.path_segments(request) {
    ["modules", ..rest] -> {
      case rest, method {
        ["share"], http.Post -> modules.share(request, context)
        ["modules", cid], http.Get -> modules.get(cid, context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    ["packages", ..rest] -> {
      case rest, method {
        ["submit"], http.Post -> packages.submit(request, context)
        ["pull"], http.Get -> packages.pull(request, context)
        // List packes
        // [], http.Get -> packages.packages(context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    ["signatories", ..rest] -> {
      case rest, method {
        ["submit"], http.Post -> signatories.submit(request, context)
        ["pull"], http.Get -> signatories.pull(request, context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    _ -> wisp.html_response("Nothing", 404)
  }
}
