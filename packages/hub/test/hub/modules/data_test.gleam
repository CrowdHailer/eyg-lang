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

pub fn insert_bundle_stores_every_module_test() {
  use conn <- helpers.with_transaction()
  let first = ir.integer(1)
  let first_cid = cid.from_tree(first)
  let second = ir.integer(2)
  let second_cid = cid.from_tree(second)
  let ip = "192.168.2.2"
  let query =
    data.insert_bundle(
      [
        #(first_cid, first),
        #(second_cid, second),
      ],
      ip,
    )
  let assert Ok(pog.Returned(count: 2, rows: [])) = pog.execute(query, conn)

  let assert Ok(pog.Returned(rows: [_], ..)) =
    pog.execute(data.get(v1.to_string(first_cid)), conn)
  let assert Ok(pog.Returned(rows: [_], ..)) =
    pog.execute(data.get(v1.to_string(second_cid)), conn)
  let assert Ok(pog.Returned(rows: [2], ..)) =
    pog.execute(data.count_uploads_by_ip(ip), conn)
}

pub fn get_unknown_cid_test() {
  use conn <- helpers.with_transaction()

  let source = ir.integer(int.random(1_000_000))
  let cid = cid.from_tree(source)
  let query = data.get(v1.to_string(cid))
  let assert Ok(pog.Returned(count: 0, rows: [])) = pog.execute(query, conn)
}
