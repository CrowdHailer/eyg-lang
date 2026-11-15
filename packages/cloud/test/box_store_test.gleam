import cloud/beam/execute
import cloud/beam/file_system
import cloud/box
import cloud/box/store
import cloud/box/transaction as tx
import eyg/hub/cache
import gleam/bit_array
import gleam/crypto
import gleam/dict
import gleam/erlang/process
import gleam/otp/actor
import gleeunit/should
import ogre/origin
import simplifile

fn path() {
  "/tmp/opencode/box-"
  <> bit_array.base64_url_encode(crypto.strong_random_bytes(12), False)
  <> ".json"
}

pub fn durable_commit_and_rejection_test() {
  let path = path()
  let runtime =
    execute.State(origin.http("localhost"), cache.ready(), dict.new())
  let assert Ok(owner) = box.start(path, box.empty(), runtime)
  let initial = box.inspect(owner.data)
  let assert Ok(root) =
    box.commit(
      owner.data,
      initial.files.root,
      [tx.Put("/hello.eyg", <<"42":utf8>>)],
      fn(_) { True },
    )
  box.commit(
    owner.data,
    root,
    [tx.Put("/hello.eyg", <<"!int_add(1, \"no\")":utf8>>)],
    fn(_) { True },
  )
  |> should.be_error
  box.inspect(owner.data).files.root |> should.equal(root)
  let assert Ok(saved) = store.load(path)
  saved.files.root |> should.equal(root)
  saved.history |> should.equal([initial.files.root])
  file_system.read(saved.files, "/hello.eyg", 0, 10)
  |> should.equal(Ok(<<"42":utf8>>))
  let assert Ok(restarted) = box.start(path, box.empty(), runtime)
  box.inspect(restarted.data) |> should.equal(saved)
  simplifile.delete(path) |> should.be_ok
}

pub fn simultaneous_writers_test() {
  let path = path()
  let runtime =
    execute.State(origin.http("localhost"), cache.ready(), dict.new())
  let assert Ok(owner) = box.start(path, box.empty(), runtime)
  let base = box.inspect(owner.data).files.root
  let replies = process.new_subject()
  process.send(
    owner.data,
    box.Commit(base, [tx.Put("/one", <<>>)], fn(_) { True }, replies),
  )
  process.send(
    owner.data,
    box.Commit(base, [tx.Put("/two", <<>>)], fn(_) { True }, replies),
  )
  let assert Ok(Ok(root)) = process.receive(replies, 1000)
  process.receive(replies, 1000) |> should.equal(Ok(Error(tx.Conflict(root))))
  simplifile.delete(path) |> should.be_ok
}

pub fn failed_persistence_does_not_publish_test() {
  let path = path()
  let runtime =
    execute.State(origin.http("localhost"), cache.ready(), dict.new())
  let assert Ok(owner) = box.start(path, box.empty(), runtime)
  let base = box.inspect(owner.data)
  // A directory in place of the temporary file forces the real write to fail.
  simplifile.create_directory(path <> ".tmp") |> should.be_ok
  box.commit(owner.data, base.files.root, [tx.Put("/one", <<>>)], fn(_) { True })
  |> should.be_error
  box.inspect(owner.data) |> should.equal(base)
  simplifile.delete(path <> ".tmp") |> should.be_ok
  simplifile.delete(path) |> should.be_ok
}

pub fn authorization_rechecked_before_publish_test() {
  let path = path()
  let runtime =
    execute.State(origin.http("localhost"), cache.ready(), dict.new())
  let assert Ok(owner) = box.start(path, box.empty(), runtime)
  let assert Ok(gate) =
    actor.new(0)
    |> actor.on_message(fn(count, reply) {
      process.send(reply, count == 0)
      actor.continue(count + 1)
    })
    |> actor.start
  let before = box.inspect(owner.data)
  box.commit(
    owner.data,
    before.files.root,
    [tx.Put("/value.eyg", <<"42":utf8>>)],
    fn(_) { process.call(gate.data, 1000, fn(reply) { reply }) },
  )
  |> should.be_error
  box.inspect(owner.data) |> should.equal(before)
  simplifile.delete(path) |> should.be_ok
}
