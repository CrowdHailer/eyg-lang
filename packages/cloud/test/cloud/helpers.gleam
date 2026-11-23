import cloud/beam/execute
import cloud/config
import cloud/data/db
import cloud/db/pool
import eyg/hub/cache
import gleam/dict
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Name}
import ogre/origin
import pog

@external(erlang, "cloud_test_ffi", "identity")
fn unsafe_global_name(atom: Atom) -> Name(a)

/// The one place where we assert the message type of this global singleton
fn test_pool_name() -> Name(pog.Message) {
  unsafe_global_name(atom.create("cloud_test_postgres_pool"))
}

pub fn start_db() {
  let assert Ok(postgres) = config.postgres()
  let assert Ok(_) = pool.start(test_pool_name(), postgres)
  Nil
}

/// Everything a test writes to the database is rolled back.
pub fn with_transaction(then) {
  let conn = pog.named_connection(test_pool_name())
  let assert Error(pog.TransactionRolledBack(Nil)) =
    pog.transaction(conn, fn(connection) {
      then(db.InTransaction(connection))
      Error(Nil)
    })
  Nil
}

/// Blocks are kept in the bucket set by the `S3_` variables, by their content so tests can share it.
pub fn state() {
  let assert Ok(bucket) = config.bucket()
  execute.State(
    origin.https("eyg.test"),
    cache.ready(),
    dict.new(),
    bucket,
    dict.new(),
  )
}
