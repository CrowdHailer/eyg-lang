import eyg/ir/dag_json
import eyg/ir/tree as ir
import gleam/int
import gleam/json
import hub/cid
import hub/helpers
import hub/modules/data
import multiformats/cid/v1
import pog

pub fn insert_and_get_module_test() {
  use conn <- helpers.with_transaction()
  let source = ir.let_("x", ir.integer(1), ir.variable("x"))
  let cid = cid.from_tree(source)
  let ip = "192.168.2.1"
  let query = data.insert(cid, source, ip)
  let assert Ok(pog.Returned(count: 1, rows: [])) = pog.execute(query, conn)

  let query = data.get(v1.to_string(cid))
  let assert Ok(pog.Returned(count: 1, rows: [module])) =
    pog.execute(query, conn)
  assert cid == module.cid
  assert Ok(source) == json.parse(module.source, dag_json.decoder(Nil))
}

pub fn insert_module_is_idempotent_test() {
  use conn <- helpers.with_transaction()
  let source = ir.let_("x", ir.integer(1), ir.variable("x"))
  let cid = cid.from_tree(source)
  let ip = "192.168.2.1"
  let query = data.insert(cid, source, ip)
  let assert Ok(pog.Returned(count: 1, rows: [])) = pog.execute(query, conn)

  // Test that a second insert inserts one more row
  let query = data.insert(cid, source, ip)
  let assert Ok(pog.Returned(count: 1, rows: [])) = pog.execute(query, conn)

  let query = data.count_uploads_by_ip(ip)
  let assert Ok(pog.Returned(count: 1, rows: [count])) =
    pog.execute(query, conn)
  assert 2 == count
}

pub fn get_unknown_cid_test() {
  use conn <- helpers.with_transaction()

  let source = ir.integer(int.random(1_000_000))
  let cid = cid.from_tree(source)
  let query = data.get(v1.to_string(cid))
  let assert Ok(pog.Returned(count: 0, rows: [])) = pog.execute(query, conn)
}
// ------------------------------------------------------------

// pub fn fixture_fragment(db) {
//   let source = ir.integer(int.random(1_000_000))
//   let assert Ok(cid) = todo as "cid.from_tree(source)"
//   let string = json.to_string(dag_json.to_data_model(source))

//   let assert Ok(fragment) = data.insert_fragment(db, string, cid)
//   fragment.cid
// }

// // pub fn insert_release_test() {
// //   use context.Context(db:, ..) <- test_context()
// //   let cid1 = fixture_fragment(db)
// //   let assert Ok(_) = data.write_release(db, "abc", 1, todo as cid1)
// //   let cid2 = fixture_fragment(db)
// //   let assert Ok(_) = data.write_release(db, "pgr", 1, todo as cid2)
// //   let cid3 = fixture_fragment(db)
// //   let assert Ok(_) = data.write_release(db, "abc", 2, todo as cid3)

// //   let package1 = g.package()
// //   let package2 = g.package()
// //   let mod1 = th.fragment_fixture(db)
// //   let archived = th.release_fixture(access, package1, mod1, db)
// //   let cid1 = archived.cid
// //   let mod2 = th.fragment_fixture(db)
// //   let _ = th.release_fixture(access, package2, mod2, db)
// //   let mod3 = th.fragment_fixture(db)
// //   let next_release =
// //     substrate.Entry(
// //       sequence: 2,
// //       previous: Some(cid1),
// //       signatory: access.0,
// //       key: { access.1 }.key_id,
// //       content: publisher.Release(package: package1, version: 2, module: mod3),
// //     )
// //   let assert Ok(_) = data.insert_release(next_release, db)

// //   // TODO test cant insert same twice
// //   // pass in previous
// //   let assert Ok([p2, p1]) = data.list_packages(db)

// //   assert p2.id == package1
// //   assert p2.version == 2
// //   // assert p2.fragment == mod3

// //   assert p1.id == package2
// //   assert p1.version == 1
// //   // assert p1.fragment == mod2

// //   let assert Ok([r2, r1]) = data.list_releases(db, package1)
// //   assert r2.package == package1
// //   assert r2.version == 2
// //   // assert r2.fragment == mod3

// //   assert r1.package == package1
// //   assert r1.version == 1
// //   // assert r1.fragment == mod1

// //   data.list_entries_from_entry(db, archived.cid)
// //   |> echo
// // }

// // pub fn first_release_version_must_be_one_test() {
// //   use context.Context(db:, ..) <- test_context()
// //   let cid1 = fixture_fragment(db)
// //   let assert Error(reason) = data.write_release(db, "abc", 0, todo as cid1)
// //   let assert pog.ConstraintViolated(constraint: "versions_are_positive", ..) =
// //     reason
// // }

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

// // pub fn reject_release_publish_with_nonexistant_fragment_test() {
// //   use context <- test_context()
// //   let source = ir.integer(int.random(1_000_000))
// //   let assert Ok(cid) = todo as "cid.from_tree(source)"
// //   let json =
// //     protocol.ReleasePublished(package_id: "abc", version: 1, fragment: cid)
// //     |> protocol.payload_encode
// //     |> json.to_string
// //   let assert Error(reason) = data.write_event(context.db, json)
// //   let assert pog.ConstraintViolated(constraint: "fk_fragment_cid", ..) = reason
// // }

// fn test_context(then) {
//   use context, _ai <- th.test_context()
//   then(context)
// }
