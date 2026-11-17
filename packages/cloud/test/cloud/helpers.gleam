import cloud/apex/context.{Context}
import cloud/apex/router
import cloud/beam/execute
import cloud/box/memory
import cloud/data/blobs
import cloud/data/db
import cloud/data/pool
import cloud/registry
import envoy
import eyg/hub/cache
import gleam/dict
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Name}
import gleam/int
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
  let assert Ok(host) = envoy.get("POSTGRES_HOST")
  let assert Ok(password) = envoy.get("POSTGRES_PASSWORD")
  let assert Ok(_) =
    pool.start(test_pool_name(), pool.Postgres(host:, password:))
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
  let assert Ok(sessions) = registry.start()
  let assert Ok(memory) = memory.start()
  Context(
    db:,
    boxes: boxes.data,
    memory: memory.data,
    sessions: sessions.data,
    state:,
    policy:,
  )
}

pub fn unique(name) {
  name <> "-" <> int.to_string(int.random(1_000_000_000))
}

/// Each state has its own blobs, kept in memory.
pub fn state() {
  let assert Ok(blobs) = blobs.start()
  execute.State(
    origin.https("eyg.test"),
    cache.ready(),
    dict.new(),
    blobs.data,
    dict.new(),
  )
}

pub fn dispatch(request, context) {
  router.route(request, context)
}
