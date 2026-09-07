import eyg/hub/publisher
import eyg/hub/signatory
import eyg/ir/tree as ir
import gleam/int
import gleam/result
import hub/cid
import hub/crypto
import hub/modules/data as modules
import hub/packages/data as packages
import hub/signatories/data as signatories
import multiformats/cid/v1
import pog

pub fn module(conn: pog.Connection) -> Result(v1.Cid, pog.QueryError) {
  let source = ir.integer(int.random(1_000_000))
  insert_module(conn, source)
}

pub fn insert_module(conn, source) {
  let cid = cid.from_tree(source)
  let query = modules.insert(cid, source, "0.0.0.0")
  use _ <- result.map(pog.execute(query, conn))
  cid
}

pub fn signatory(conn) {
  let keypair = crypto.generate_key()

  let first = signatory.first(keypair.key_id)
  let payload = signatory.to_bytes(first)
  let _signature = crypto.sign(payload, keypair)
  let cid = cid.from_block(payload)
  let query = signatories.insert_entry(cid, signatory.encode(first))
  use pog.Returned(rows:, ..) <- result.map(pog.execute(query, conn))
  let assert [entry] = rows
  #(entry, keypair)
}

/// The package is owned by the entity allow it to publish new releases
pub fn own_package(
  conn: pog.Connection,
  package: String,
  entity: v1.Cid,
) -> Result(Nil, pog.QueryError) {
  let query = packages.record_owner(package, v1.to_string(entity))
  use _ <- result.map(pog.execute(query, conn))
  Nil
}

pub fn first_package(
  conn: pog.Connection,
  package: String,
  source: ir.Node(a),
) -> v1.Cid {
  let assert Ok(#(signatory, keypair)) = signatory(conn)

  let assert Ok(Nil) = own_package(conn, package, signatory.cid)
  let assert Ok(module) = insert_module(conn, source)
  let first = publisher.first(signatory.cid, keypair.key_id, package, module)
  let query = packages.insert_release(first)
  let assert Ok(_) = pog.execute(query, conn)
  module
}
