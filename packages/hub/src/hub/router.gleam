import wisp

pub fn route(_request, _context) {
  wisp.html_response("Ok", 200)
}
