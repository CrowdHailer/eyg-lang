import gleam/bytes_tree
import gleam/http
import gleam/http/request.{Request}
import gleam/http/response
import hub/artifacts/controller as artifacts
import hub/modules/controller as modules
import hub/packages/controller as packages
import hub/proxy/controller as proxy
import hub/server/context
import hub/signatories/controller as signatories
import wisp

pub fn route(request: wisp.Request, context: context.Context) -> wisp.Response {
  use <- wisp.log_request(request)
  let Request(method:, ..) = request
  case request.path_segments(request) {
    ["modules", ..rest] -> {
      use <- cors(request)
      case rest, method {
        ["share"], http.Post -> modules.share(request, context)
        [cid], http.Get -> modules.get(cid, context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    ["packages", ..rest] -> {
      use <- cors(request)
      case rest, method {
        ["submit"], http.Post -> packages.submit(request, context)
        ["pull"], http.Get -> packages.pull(request, context)
        [name, "owner"], http.Get -> packages.owner(name, context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    ["signatories", ..rest] -> {
      use <- cors(request)
      case rest, method {
        ["submit"], http.Post -> signatories.submit(request, context)
        ["pull"], http.Get -> signatories.pull(request, context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    ["artifacts", ..rest] -> {
      case rest, method {
        [], http.Post -> artifacts.share(request, context)
        [id], http.Get -> artifacts.get(id, context)
        [id, "files", ..path], http.Get -> artifacts.file(id, path, context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    ["artifact", ..rest] -> {
      case rest, method {
        [id], http.Get -> artifacts.page(id, context)
        _, _ -> wisp.html_response("Nothing", 404)
      }
    }
    ["proxy", service, ..rest] -> proxy.to(service, rest, request)
    _ -> wisp.html_response("Nothing", 404)
  }
}

fn cors(request: wisp.Request, then: fn() -> wisp.Response) -> wisp.Response {
  let empty = wisp.Bytes(bytes_tree.from_string(""))
  let response = case request.method {
    http.Options ->
      response.new(204)
      |> response.set_body(empty)
      |> wisp.set_header("access-control-allow-methods", "GET, POST")
      |> wisp.set_header("access-control-allow-headers", "content-type")
    _ -> then()
  }
  wisp.set_header(response, "access-control-allow-origin", "*")
}
