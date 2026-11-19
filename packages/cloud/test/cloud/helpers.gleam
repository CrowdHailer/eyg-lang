import cloud/apex/context.{Context}
import cloud/apex/router
import cloud/beam/execute
import cloud/box/memory
import cloud/data/blobs
import cloud/data/pool
import envoy
import eyg/hub/cache
import gleam/dict
import gleam/erlang/atom.{type Atom}
import gleam/erlang/process.{type Name}
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
    pog.transaction(conn, fn(db) {
      then(db)
      Error(Nil)
    })
  Nil
}

/// Each context keeps its own boxes in memory.
pub fn context(then) {
  use db <- with_transaction()
  let assert Ok(memory) = memory.start()
  let assert Ok(code) = simplifile.read("policy.eyg")
  let assert #(Ok(policy), state) = execute.load_policy(code, state())
  then(Context(db:, memory: memory.data, state:, policy:))
}

/// Each state has its own blobs, kept in memory.
pub fn state() {
  let assert Ok(blobs) = blobs.start()
  execute.State(origin.https("eyg.test"), cache.ready(), dict.new(), blobs.data)
}

pub fn dispatch(request, context) {
  router.route(request, context)
}
