import eyg/hub/publisher
import eyg/ir/tree as ir
import gleam/int
import hub/cid
import hub/fixtures
import hub/generators as g
import hub/helpers
import hub/packages/data
import multiformats/cid/v1
import pog
import untethered/substrate

pub fn insert_multiple_releases_test() {
  use conn <- helpers.with_transaction()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(conn)

  let package1 = g.package()
  let assert Ok(cid1) = fixtures.module(conn)
  let entry = publisher.first(signatory.entity, keypair.key_id, package1, cid1)
  let query = data.insert_release(entry)
  let assert Ok(pog.Returned(rows: [archived], ..)) = pog.execute(query, conn)

  let assert Ok(cid2) = fixtures.module(conn)
  let entry =
    publisher.follow(signatory.entity, keypair.key_id, package1, cid2, archived)
  let query = data.insert_release(entry)
  let assert Ok(_archived) = pog.execute(query, conn)

  let query = data.list_releases(package1)
  let assert Ok(pog.Returned(rows:, ..)) = pog.execute(query, conn)

  let assert [r2, r1] = rows
  assert r2.package == package1
  assert r2.version == 2
  assert r2.module == cid2 |> v1.to_string

  assert r1.package == package1
  assert r1.version == 1
  assert r1.module == cid1 |> v1.to_string
}

pub fn insert_multiple_packages_test() {
  use conn <- helpers.with_transaction()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(conn)

  let package1 = g.package()
  let assert Ok(cid1) = fixtures.module(conn)
  let entry = publisher.first(signatory.entity, keypair.key_id, package1, cid1)
  let query = data.insert_release(entry)
  let assert Ok(pog.Returned(rows: [_archived], ..)) = pog.execute(query, conn)

  let package2 = g.package()
  let assert Ok(cid2) = fixtures.module(conn)
  let entry = publisher.first(signatory.entity, keypair.key_id, package2, cid2)
  let query = data.insert_release(entry)
  let assert Ok(_archived) = pog.execute(query, conn)

  let query = data.list_packages()
  let assert Ok(pog.Returned(rows:, ..)) = pog.execute(query, conn)

  let assert [p2, p1] = rows
  assert p2.id == package2
  assert p2.version == 1
  assert p2.module == cid2 |> v1.to_string

  assert p1.id == package1
  assert p1.version == 1
  assert p1.module == cid1 |> v1.to_string
}

pub fn reject_release_with_nonexistant_fragment_test() {
  use conn <- helpers.with_transaction()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(conn)
  let source = ir.integer(int.random(1_000_000))
  let cid = cid.from_tree(source)
  let package1 = g.package()
  let entry = publisher.first(signatory.entity, keypair.key_id, package1, cid)
  let query = data.insert_release(entry)
  let assert Error(reason) = pog.execute(query, conn)
  let assert pog.ConstraintViolated(
    constraint: "package_entries_module_fkey",
    ..,
  ) = reason
}

pub fn first_version_cant_be_less_than_one_test() {
  use conn <- helpers.with_transaction()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(conn)

  let assert Ok(cid1) = fixtures.module(conn)
  let package1 = g.package()
  let entry = publisher.first(signatory.entity, keypair.key_id, package1, cid1)
  let entry = substrate.Entry(..entry, sequence: 0)
  let query = data.insert_release(entry)
  let assert Error(reason) = pog.execute(query, conn)
  assert pog.PostgresqlError(
      "P0001",
      "raise_exception",
      "Root event (no previous) must have sequence 1, got 0",
    )
    == reason
}

pub fn first_version_cant_be_greater_than_one_test() {
  use conn <- helpers.with_transaction()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(conn)

  let assert Ok(cid1) = fixtures.module(conn)
  let package1 = g.package()
  let entry = publisher.first(signatory.entity, keypair.key_id, package1, cid1)
  let entry = substrate.Entry(..entry, sequence: 2)
  let query = data.insert_release(entry)
  let assert Error(reason) = pog.execute(query, conn)
  assert pog.PostgresqlError(
      "P0001",
      "raise_exception",
      "Root event (no previous) must have sequence 1, got 2",
    )
    == reason
}

pub fn cant_republish_release_test() {
  use conn <- helpers.with_transaction()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(conn)

  let package = g.package()
  let assert Ok(cid1) = fixtures.module(conn)
  let entry = publisher.first(signatory.entity, keypair.key_id, package, cid1)

  let query = data.insert_release(entry)
  let assert Ok(_) = pog.execute(query, conn)

  let assert Ok(cid2) = fixtures.module(conn)
  let entry = publisher.first(signatory.entity, keypair.key_id, package, cid2)

  let query = data.insert_release(entry)
  let assert Error(reason) = pog.execute(query, conn)
  let assert pog.ConstraintViolated(constraint:, ..) = reason
  assert "package_entries_unique_release_version" == constraint
}
