import envoy
import gleam/crypto
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Name}
import gleam/http
import gleam/http/request.{Request}
import gleam/http/response.{Response}
import hub/cid
import hub/config
import hub/db/pool
import hub/router
import hub/server/context
import ogre/operation
import ogre/origin
import pog
import wisp/simulate

pub fn random_cid() {
  cid.from_block(crypto.strong_random_bytes(40))
}

@external(erlang, "hub_ffi", "identity")
fn unsafe_global_name(atom: Atom) -> Name(a)

/// The one place where we assert the message type of this global singleton
fn test_pool_name() -> Name(pog.Message) {
  unsafe_global_name(atom.create("server_test_postgres_pool"))
}

pub fn with_transaction(then) {
  let conn = pog.named_connection(test_pool_name())

  let assert Error(pog.TransactionRolledBack(Nil)) =
    pog.transaction(conn, fn(conn) {
      then(conn)
      Error(Nil)
    })
}

pub fn start_db() {
  let assert Ok(postgres_host) = envoy.get("POSTGRES_HOST")
  let assert Ok(postgres_password) = envoy.get("POSTGRES_PASSWORD")
  let postgres =
    config.Postgres(host: postgres_host, password: postgres_password)
  let assert Ok(_started) = pool.start(test_pool_name(), postgres)
  Nil
}

pub fn dispatch(operation, context) {
  let request = operation.to_request(operation, origin.https("eyg.test"))

  let Request(body:, ..) = request
  let unnecessary =
    simulate.request(http.Get, "")
    |> simulate.bit_array_body(body)
  let request = Request(..request, body: unnecessary.body)
  let response = router.route(request, context)
  let body = simulate.read_body_bits(response)
  Response(..response, body:)
}

pub fn web_context(then) {
  use conn <- with_transaction()
  then(context.Context(secret_key_base: "123", db: conn))
}
