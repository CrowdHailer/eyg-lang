import cloud/apex/access
import cloud/apex/context.{Context}
import cloud/apex/server
import cloud/beam/execute
import cloud/config
import cloud/data/db
import cloud/db/pool
import cloud/live
import cloud/registry
import eyg/hub/cache
import gleam/dict
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Name}
import gleam/int
import howdy/testing
import ogre/origin
import pog
import simplifile

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

pub fn context(then) {
  use db <- with_transaction()
  then(context_for(db))
}

/// For tests that make queries at the same time, which one connection cannot.
/// Writes are kept, so use names no other test uses.
pub fn pool_context() {
  context_for(db.Pool(pog.named_connection(test_pool_name())))
}

fn context_for(db) {
  let assert Ok(policy) = simplifile.read("policy.eyg")
  let state = state()
  let assert Ok(boxes) = registry.start()
  let assert Ok(shells) = registry.start()
  let assert Ok(chats) = registry.start()
  let assert Ok(live) = live.start()
  Context(
    db:,
    boxes: boxes.data,
    shells: shells.data,
    chats: chats.data,
    state:,
    policy:,
    llms: dict.new(),
    live:,
  )
}

pub fn unique(name) {
  name <> "-" <> int.to_string(int.random(1_000_000_000))
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

pub fn dispatch(request, context) {
  testing.send(request, server.app(context, access.Local))
}

/// Wait for the check to pass, checking every 10ms.
pub fn wait_until(check: fn() -> Bool, attempts: Int) -> Nil {
  case check(), attempts {
    True, _ -> Nil
    False, 0 -> panic as "timed out waiting"
    False, _ -> {
      process.sleep(10)
      wait_until(check, attempts - 1)
    }
  }
}
