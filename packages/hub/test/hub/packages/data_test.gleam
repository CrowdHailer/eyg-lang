import eyg/hub/publisher
import eyg/ir/tree as ir
import gleam/int
import hub/cid
import hub/fixtures
import hub/generators as g
import hub/helpers
import hub/packages/data
import pog
import untethered/substrate

// insert multiple packages
// insert multiple releases
pub fn insert_release_test() {
  use conn <- helpers.with_transaction()
  let assert Ok(#(signatory, keypair)) = fixtures.signatory(conn)

  let assert Ok(cid1) = fixtures.module(conn)
  let package1 = g.package()
  let entry = publisher.first(signatory.entity, keypair.key_id, package1, cid1)
  let query = data.insert_release(entry)
  let assert Ok(_) = pog.execute(query, conn)
  // let cid2 = fixture_fragment(db)
  // let assert Ok(_) = data.write_release(db, "pgr", 1, todo as cid2)
  // let cid3 = fixture_fragment(db)
  // let assert Ok(_) = data.write_release(db, "abc", 2, todo as cid3)

  // let package2 = g.package()
  // let mod1 = th.fragment_fixture(db)
  // let archived = th.release_fixture(access, package1, mod1, db)
  // let cid1 = archived.cid
  // let mod2 = th.fragment_fixture(db)
  // let _ = th.release_fixture(access, package2, mod2, db)
  // let mod3 = th.fragment_fixture(db)
  // let next_release =
  //   substrate.Entry(
  //     sequence: 2,
  //     previous: Some(cid1),
  //     signatory: access.0,
  //     key: { access.1 }.key_id,
  //     content: publisher.Release(package: package1, version: 2, module: mod3),
  //   )
  // let assert Ok(_) = data.insert_release(next_release, db)

  // // TODO test cant insert same twice
  // // pass in previous
  // let assert Ok([p2, p1]) = data.list_packages(db)

  // assert p2.id == package1
  // assert p2.version == 2
  // // assert p2.fragment == mod3

  // assert p1.id == package2
  // assert p1.version == 1
  // // assert p1.fragment == mod2

  // let assert Ok([r2, r1]) = data.list_releases(db, package1)
  // assert r2.package == package1
  // assert r2.version == 2
  // // assert r2.fragment == mod3

  // assert r1.package == package1
  // assert r1.version == 1
  // // assert r1.fragment == mod1

  // data.list_entries_from_entry(db, archived.cid)
  // |> echo
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

pub fn first_release_version_must_be_one_test() {
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
// hash must match

// // pub fn cant_insert_out_of_order_version_test() {
// //   use context.Context(db:, ..) <- test_context()
// //   let cid1 = fixture_fragment(db)
// //   let assert Ok(_) = data.write_release(db, "abc", 1, todo as cid1)
// //   let cid2 = fixture_fragment(db)
// //   let assert Error(reason) = data.write_release(db, "abc", 1, todo as cid2)
// //   let assert pog.ConstraintViolated(constraint: "unique_package_version", ..) =
// //     reason
// // }

// //   let package = "package"
// //   let cid1 = th.fragment_fixture(db)
// //   let _ = th.release_fixture(access, package, cid1, db)

// //   let cid1 = th.fragment_fixture(db)
// //   let assert Error(pog.ConstraintViolated(constraint:, ..)) =
// //     publisher.first(access.0, { access.1 }.key_id, package, cid1)
// //     |> data.insert_release(db)
// //   assert "registry_events_unique_release_version" == constraint
// // }
