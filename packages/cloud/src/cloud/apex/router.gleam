import cloud/apex/context
import wisp

pub fn route(request, _context: context.Context) {
  case request {
    _ -> wisp.html_response("Nothing", 404)
  }
}
