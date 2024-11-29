import eyg/hub/archive
import eyg/hub/archive/client
import eyg/hub/archive/server
import eygir/expression
import gleam/http
import gleam/http/request
import gleam/option.{None}
import gleeunit/should
import javascript/mutable_reference as ref

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
  let backend = ref.new(archive.empty())
  let source = expression.Str("Hello.")
  // client code assumes it's valid
  let response =
    source
    |> client.publish_request(base, "foo", 0, _)
    |> server.handle(backend)
    |> client.publish_response
    |> should.be_ok
  response
  |> should.equal(Nil)
}
