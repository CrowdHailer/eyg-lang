import cloud/config
import cloud/db/pool
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Name}
import pog

@external(erlang, "cloud_ffi", "identity")
fn unsafe_global_name(atom: Atom) -> Name(a)

/// The one place where we assert the message type of this global singleton
fn test_pool_name() -> Name(pog.Message) {
  unsafe_global_name(atom.create("cloud_test_postgres_pool"))
}

/// Note that this helper cannot be used if code also executes a transaction.
/// Postgres does not support nested transactions.
/// 
/// Solutions:
/// - use savepoints in application code
/// - use disposable database/schema for testing. <- this is my prefered approach
pub fn with_transaction(then) {
  let conn = pog.named_connection(test_pool_name())

  let assert Error(pog.TransactionRolledBack(Nil)) =
    pog.transaction(conn, fn(conn) {
      then(conn)
      Error(Nil)
    })
}

pub fn start_db() {
  let assert Ok(postgres) = config.postgres()
  let assert Ok(_started) = pool.start(test_pool_name(), postgres)
  Nil
}
