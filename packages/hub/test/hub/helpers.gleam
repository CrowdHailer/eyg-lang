import envoy
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Name}
import hub/db/pool
import pog

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
  let assert Ok(postgres_password) = envoy.get("POSTGRES_PASSWORD")
  let assert Ok(_started) = pool.start(test_pool_name(), postgres_password)
  Nil
}
