import eyg/hub/archive
import eyg/hub/archive/client
import eyg/hub/archive/server
import eygir/expression
import gleam/http
import gleam/http/request
import gleam/option.{None}
import gleeunit/should
import javascript/mutable_reference as ref
import midas/task as t

// separate registry and package test
// somethning that is code and authentication
// state and storage log 
const base = request.Request(
  http.Get,
  [],
  <<>>,
  http.Https,
  "eyg.test",
  None,
  "",
  None,
)

pub fn publish_first_edition_test() {
  let server = archive.empty()
  let source = expression.Str("Hello.")
  // client code assumes it's valid

  let #(request, resume) =
    t.expect_fetch(client.publish(base, "foo", 0, source))
    |> should.be_ok()
  let #(response, server) = server.do_handle(request, server)
  t.expect_done(resume(Ok(response)))
  |> should.be_ok()
  |> should.equal(Nil)
}
