import eyg/hub/signatory
import eyg/ir/tree as ir
import gleam/int
import gleam/result
import hub/cid
import hub/crypto
import hub/modules/data as modules
import hub/signatories/data as signatories
import pog

pub fn module(conn) {
  let source = ir.integer(int.random(1_000_000))
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
