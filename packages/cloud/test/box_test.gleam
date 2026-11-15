import cloud/beam/execute
import cloud/beam/file_system
import cloud/box/check
import cloud/box/transaction as tx
import eyg/hub/cache
import eyg/interpreter/value as v
import gleam/dict
import gleeunit/should
import ogre/origin

fn runtime() {
  execute.State(origin.http("localhost"), cache.ready(), dict.new())
}

fn empty() {
  file_system.new(dict.new())
}

pub fn batch_and_conflict_test() {
  let files = empty()
  let assert Ok(candidate) =
    tx.prepare(
      files,
      files.root,
      [
        tx.Put("/a.eyg", <<"1":utf8>>),
        tx.Put("/b.eyg", <<"!int_add(import \"a.eyg\", 1)":utf8>>),
      ],
      fn(_) { True },
    )
  let assert Ok(#(modules, _)) = check.validate(candidate, runtime())
  let assert Ok(module) = dict.get(modules, "/b.eyg")
  module.value |> should.equal(v.Integer(2))
  tx.prepare(candidate, files.root, [], fn(_) { True })
  |> should.equal(Error(tx.Conflict(candidate.root)))
  let assert Ok(updated) =
    tx.prepare(
      candidate,
      candidate.root,
      [
        tx.Put("/a.eyg", <<"\"hello\"":utf8>>),
        tx.Put("/b.eyg", <<"import \"a.eyg\"":utf8>>),
      ],
      fn(_) { True },
    )
  check.validate(updated, runtime()) |> should.be_ok
  file_system.read(candidate, "/a.eyg", 0, 10) |> should.equal(Ok(<<"1":utf8>>))
}

pub fn dependent_invalid_update_test() {
  let files = empty()
  let assert Ok(candidate) =
    tx.prepare(
      files,
      files.root,
      [
        tx.Put("/a.eyg", <<"\"not a number\"":utf8>>),
        tx.Put("/b.eyg", <<"!int_add(import \"a.eyg\", 1)":utf8>>),
      ],
      fn(_) { True },
    )
  check.validate(candidate, runtime()) |> should.be_error
}

pub fn canonical_authorization_and_failed_batch_test() {
  let files = empty()
  tx.prepare(
    files,
    files.root,
    [tx.Put("/allowed/../secret", <<>>)],
    fn(change) { tx.path(change) == "/allowed" },
  )
  |> should.equal(Error(tx.Denied("/secret")))
  tx.prepare(
    files,
    files.root,
    [tx.Put("/first", <<>>), tx.Delete("/missing")],
    fn(_) { True },
  )
  |> should.be_error
  file_system.read_directory(files, "/") |> should.equal(Ok([]))
}

pub fn imports_validation_test() {
  let files = empty()
  let assert Ok(files) =
    tx.prepare(
      files,
      files.root,
      [
        tx.MakeDirectory("/routes"),
        tx.Put("/routes/a.eyg", <<"1":utf8>>),
        tx.Put("/routes/b.eyg", <<"2":utf8>>),
        tx.Put("/all.eyg", <<"import \"/routes/:{path}.eyg\"":utf8>>),
        tx.Put("/text.txt", <<"hi":utf8>>),
        tx.Put("/text.eyg", <<"import \"text.txt\"":utf8>>),
      ],
      fn(_) { True },
    )
  let assert Ok(#(modules, _)) = check.validate(files, runtime())
  let assert Ok(module) = dict.get(modules, "/text.eyg")
  module.value |> should.equal(v.Binary(<<"hi":utf8>>))
  let assert Ok(bad) =
    tx.prepare(
      files,
      files.root,
      [tx.Put("/routes/c.eyg", <<"\"wrong\"":utf8>>)],
      fn(_) { True },
    )
  check.validate(bad, runtime()) |> should.be_error
}

pub fn cycles_and_effects_test() {
  let files = empty()
  let assert Ok(cycle) =
    tx.prepare(
      files,
      files.root,
      [
        tx.Put("/a.eyg", <<"import \"b.eyg\"":utf8>>),
        tx.Put("/b.eyg", <<"import \"a.eyg\"":utf8>>),
      ],
      fn(_) { True },
    )
  check.validate(cycle, runtime()) |> should.be_error
  check.prepare(
    check.parse("perform Abort(\"invalid\")") |> should.be_ok,
    runtime(),
  )
  |> should.be_error
  check.prepare(
    check.parse("perform StandardOut(\"no\")") |> should.be_ok,
    runtime(),
  )
  |> should.be_error
  check.prepare(
    check.parse("(_) -> { perform StandardOut(\"yes\") }") |> should.be_ok,
    runtime(),
  )
  |> should.be_ok
}

pub fn moving_package_references_are_not_snapshot_dependencies_test() {
  let assert Ok(source) = check.parse("(_) -> { @standard }")
  check.prepare(source, runtime()) |> should.be_error
}
